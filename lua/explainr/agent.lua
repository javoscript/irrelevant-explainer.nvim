local M = {}

local function nonempty(text)
  return type(text) == "string" and text:find("%S") ~= nil
end

local function error_text(value)
  if type(value) == "string" then return value end
  if type(value) == "table" then
    if type(value.message) == "string" then return value.message end
    if type(value.data) == "table" and type(value.data.message) == "string" then return value.data.message end
    if type(value.name) == "string" then return value.name end
  end
  return vim.inspect(value)
end

local function events(stdout)
  local result = {}
  for line in (stdout .. "\n"):gmatch("([^\n]*)\n") do
    if nonempty(line) then
      local ok, event = pcall(vim.json.decode, line)
      if not ok or type(event) ~= "table" or type(event.type) ~= "string" then
        return nil, "invalid JSON event output (expected one event per line)"
      end
      result[#result + 1] = event
    end
  end
  return result
end

local function opencode(stream)
  local messages, order = {}, {}
  for _, event in ipairs(stream) do
    if event.type == "error" then return nil, "OpenCode error: " .. error_text(event.error) end
    if event.type == "text" then
      local part = event.part
      if type(part) ~= "table" or part.type ~= "text" or type(part.messageID) ~= "string"
        or not nonempty(part.messageID) or type(part.text) ~= "string" then
        return nil, "invalid OpenCode text event"
      end
      local message = messages[part.messageID]
      if not message then
        message = { parts = {}, ids = {}, incomplete = {} }
        messages[part.messageID] = message
        order[#order + 1] = part.messageID
      end
      -- Completion updates for the same part replace, rather than duplicate, it.
      local id = part.id or (#message.parts + 1)
      local index = message.ids[id]
      if not index then
        index = #message.parts + 1
        message.ids[id] = index
        message.parts[index] = ""
      end
      local completed = type(part.time) == "table" and type(part.time["end"]) == "number"
      if not completed then
        message.incomplete[id] = true
      else
        message.incomplete[id] = nil
        message.parts[index] = part.text
      end
    end
  end
  local final = messages[order[#order]]
  if not final or #final.parts == 0 or next(final.incomplete) then
    return nil, "OpenCode output has no completed final text message"
  end
  -- Message order is first appearance, not whichever earlier part finishes last.
  return table.concat(final.parts)
end

local function codex(stream)
  local final, completed, pending
  for _, event in ipairs(stream) do
    if event.type == "error" or event.type == "turn.failed" then
      return nil, "Codex " .. event.type .. ": " .. error_text(event.error or event.message)
    elseif event.type == "turn.started" then
      final, completed, pending = nil, false, false
    elseif event.type == "turn.completed" then
      completed = not pending
    elseif event.type == "item.completed" or event.type == "item.started" or event.type == "item.updated" then
      local item = event.item
      if type(item) ~= "table" or type(item.type) ~= "string" then
        return nil, "invalid Codex item event"
      end
      if item.type == "agent_message" then
        completed = false
        pending = event.type ~= "item.completed"
        if not pending then
          if type(item.text) ~= "string" then return nil, "invalid Codex agent_message text" end
          final = item.text
        end
      end
    end
  end
  if not completed or final == nil then return nil, "Codex output has no completed final turn and agent_message" end
  return final
end

--- Decode captured transport output; explanation/schema validation belongs to the caller.
function M.decode(output, stdout, stderr, exit_code)
  stdout, stderr = stdout or "", stderr or ""
  local final, err
  if type(output) == "function" then
    local ok
    ok, final, err = pcall(output, stdout, stderr, exit_code)
    if not ok then err, final = "custom decoder failed: " .. tostring(final), nil end
  elseif output == "plain" then
    final = stdout
  elseif output == "opencode" or output == "codex" then
    local stream
    stream, err = events(stdout)
    if stream then
      if output == "opencode" then final, err = opencode(stream)
      else final, err = codex(stream) end
    end
  else
    err = "unsupported agent output decoder: " .. tostring(output)
  end
  -- Even a custom decoder cannot promote an unsuccessful process to success.
  if exit_code ~= 0 then
    local detail = nonempty(stderr) and stderr or (err ~= nil and error_text(err) or "")
    return nil, "agent exited with status " .. tostring(exit_code) .. (nonempty(detail) and (": " .. detail) or "")
  end
  if err ~= nil then return nil, error_text(err) end
  if not nonempty(final) then return nil, "agent returned empty or incomplete explanation output" end
  return final
end

--- Start one argv invocation. All results (including launch errors) use a scheduled callback.
function M.run(prompt, ai_config, cwd, callback)
  if type(callback) ~= "function" then return nil, "agent callback must be a function" end
  local function reject(err)
    vim.schedule(function() callback(nil, err) end)
    return nil, err
  end
  if type(prompt) ~= "string" then return reject("agent prompt must be a string") end
  if type(ai_config) ~= "table" or type(ai_config.command) ~= "table"
    or not vim.islist(ai_config.command) or #ai_config.command == 0 then
    return reject("ai.command must be a nonempty argv list")
  end
  for _, arg in ipairs(ai_config.command) do
    if type(arg) ~= "string" or arg == "" or arg:find("\0", 1, true) then
      return reject("ai.command arguments must be nonempty strings without NUL bytes")
    end
  end
  local output, timeout = ai_config.output or "plain", ai_config.timeout_ms or 300000
  if type(output) ~= "function" and output ~= "plain" and output ~= "opencode" and output ~= "codex" then
    return reject("unsupported agent output decoder: " .. tostring(output))
  end
  if type(timeout) ~= "number" or timeout <= 0 or timeout % 1 ~= 0 or timeout == math.huge then
    return reject("ai.timeout_ms must be a positive finite integer")
  end

  local stdout, stderr, io_error = {}, {}, nil
  local process, timer, result, stopped, queued, delivered
  local function close_timer()
    if timer then timer:stop(); timer:close(); timer = nil end
  end
  local function deliver()
    if queued then return end
    queued = true
    vim.schedule(function()
      if delivered then return end
      delivered = true
      local final, err
      if stopped then err = stopped
      elseif io_error then err = io_error
      elseif result.signal and result.signal ~= 0 then err = "agent interrupted by signal " .. result.signal
      else final, err = M.decode(output, table.concat(stdout), table.concat(stderr), result.code) end
      callback(final, err)
    end)
  end
  local function stop(reason)
    if delivered or stopped then return end
    stopped = reason
    close_timer()
    -- Kill the owned local process, not unrelated provider/server processes.
    if process then pcall(process.kill, process, 9) end
    deliver()
  end
  local function capture(chunks)
    return function(err, data)
      if err then io_error = "agent stream error: " .. tostring(err) end
      if data then chunks[#chunks + 1] = data end
    end
  end
  local ok, spawned = pcall(vim.system, ai_config.command, {
    cwd = cwd,
    stdin = prompt, -- vim.system writes these bytes and closes stdin (EOF).
    text = false,
    stdout = capture(stdout),
    stderr = capture(stderr),
  }, function(completed)
    result = completed
    close_timer()
    deliver()
  end)
  if not ok then return reject("could not start agent: " .. tostring(spawned)) end
  process = spawned
  timer = vim.uv.new_timer()
  timer:start(timeout, 0, function() stop("agent timed out after " .. timeout .. " ms") end)
  return { cancel = function() stop("agent cancelled") end }
end

return M
