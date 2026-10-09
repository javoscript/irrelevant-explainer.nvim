local agent = require("irrelevant_explainer.agent")
local fixture = vim.fn.getcwd() .. "/tests/fixtures/agent.py"
local answer = '{"version":1,"notes":[]}'
local progress = '{"version":1,"notes":[],"progress":true}'

local function wire(values)
  local lines = {}
  for _, value in ipairs(values) do lines[#lines + 1] = vim.json.encode(value) end
  return table.concat(lines, "\n") .. "\n"
end
local function text(message, id, value, complete)
  return { type = "text", part = { type = "text", id = id, messageID = message, text = value,
    time = complete == false and { start = 1 } or { start = 1, ["end"] = 2 } } }
end
local function item(kind, value)
  return { type = kind, item = { type = "agent_message", text = value } }
end
local function failure(output, stdout, match, status, stderr)
  local value, err = agent.decode(output, stdout, stderr or "", status or 0)
  T.eq(nil, value)
  assert(type(err) == "string" and err:find(match, 1, true), vim.inspect(err))
end
local function start(mode, output, timeout, prompt, cwd, args)
  local state = { count = 0 }
  local command = { fixture, mode }
  vim.list_extend(command, args or {})
  state.invocation, state.launch_error = agent.run(prompt or "fixture prompt", {
    command = command, output = output or "plain", timeout_ms = timeout or 2000,
  }, cwd or vim.fn.getcwd(), function(value, err)
    state.count = state.count + 1
    state.value, state.err, state.fast = value, err, vim.in_fast_event()
  end)
  assert(state.invocation, state.launch_error)
  T.eq(0, state.count)
  return state
end
local function wait(state)
  assert(vim.wait(3000, function() return state.count > 0 end, 5), "agent callback did not arrive")
  T.eq(1, state.count)
  T.eq(false, state.fast)
  return state.value, state.err
end
local function spy(run)
  local original, calls, processes, exits = vim.system, {}, {}, {}
  vim.system = function(command, options, callback)
    -- Any fallback to a real installed CLI fails before it can start.
    T.eq(fixture, command[1])
    calls[#calls + 1] = vim.deepcopy(command)
    local process = original(command, options, function(result)
      exits[#exits + 1] = result
      callback(result)
    end)
    processes[#processes + 1] = process
    return process
  end
  local ok, err = xpcall(function() run(calls, processes, exits) end, debug.traceback)
  vim.system = original
  assert(ok, err)
end

T.test("plain preserves exact final bytes; JSON/schema belongs to parent", function()
  T.eq(" \n" .. answer .. "\r\n", agent.decode("plain", " \n" .. answer .. "\r\n", "diagnostic", 0))
  T.eq("not JSON", agent.decode("plain", "not JSON", "", 0))
  failure("plain", "\n \t", "empty")
  failure("plain", answer, "authentication", 3, "authentication required")
end)

T.test("OpenCode groups final message parts and ignores schema-shaped progress/tools", function()
  local stream = wire({ text("early", "p", progress),
    { type = "tool_use", part = { text = answer } }, { type = "reasoning", part = { text = answer } },
    text("final", "a", '{"version":1,'), text("early", "late", "late earlier message part"),
    text("final", "b", '"notes":[]}'), text("final", "b", '"notes":[]}') })
  T.eq(answer, agent.decode("opencode", stream, "", 0))
  local delayed = wire({ text("final", "a", "partial", false),
    text("final", "b", '"notes":[]}'), text("final", "a", '{"version":1,') })
  T.eq(answer, agent.decode("opencode", delayed, "", 0))
end)

T.test("OpenCode incomplete final text, malformed events, empty and error override partial text", function()
  failure("opencode", wire({ text("early", "p", progress), text("final", "a", answer, false) }), "completed final")
  failure("opencode", wire({ text("final", "a", answer), text("final", "b", "partial", false) }), "completed final")
  failure("opencode", wire({ { type = "text", part = { text = answer } } }), "invalid OpenCode")
  failure("opencode", wire({ text("final", "a", answer), { type = "error", error = { data = { message = "quota" } } } }), "quota")
  failure("opencode", wire({ text("final", "a", answer), { type = "error", error = { message = "quota" } } }), "quota", 1)
  failure("opencode", wire({ text("final", "a", answer) }), "status 2", 2)
  failure("opencode", "", "completed final")
  failure("opencode", wire({ text("final", "a", answer) }) .. '{"type":', "invalid JSON")
end)

T.test("Codex selects last completed agent_message only after successful turn completion", function()
  local stream = wire({ { type = "thread.started" }, { type = "turn.started" },
    item("item.completed", progress), item("item.started", progress), item("item.updated", progress),
    { type = "item.completed", item = { type = "reasoning", text = progress } },
    item("item.completed", answer), { type = "turn.completed" } })
  T.eq(answer, agent.decode("codex", stream, "", 0))
  failure("codex", wire({ item("item.completed", answer) }), "completed final turn")
  failure("codex", wire({ item("item.updated", answer), { type = "turn.completed" } }), "completed final turn")
  failure("codex", wire({ item("item.completed", progress), item("item.started", answer), { type = "turn.completed" } }), "completed final turn")
end)

T.test("Codex failures and a new incomplete turn override earlier success", function()
  local prefix = wire({ item("item.completed", answer), { type = "turn.completed" } })
  failure("codex", prefix .. wire({ { type = "turn.failed", error = { message = "quota" } } }), "quota")
  failure("codex", prefix .. wire({ { type = "turn.failed", error = { message = "quota" } } }), "quota", 1)
  failure("codex", prefix .. wire({ { type = "error", message = "login required" } }), "login required")
  failure("codex", prefix .. wire({ { type = "turn.started" } }), "completed final turn")
  failure("codex", prefix .. wire({ item("item.updated", answer) }), "completed final turn")
  failure("codex", prefix, "status 1", 1)
  failure("codex", wire({ { type = "turn.completed" } }), "completed final turn")
  failure("codex", wire({ { type = "item.completed", item = { type = "agent_message" } } }), "invalid Codex")
end)

T.test("custom decoder receives stdout/stderr/status and cannot override nonzero exit", function()
  local seen
  local decoder = function(stdout, stderr, status) seen = { stdout, stderr, status }; return answer end
  T.eq(answer, agent.decode(decoder, "out", "err", 0))
  T.eq({ "out", "err", 0 }, seen)
  failure(decoder, "out", "status 7", 7, "err")
  T.eq({ "out", "err", 7 }, seen)
  failure(function() error("decoder exception") end, "", "decoder exception")
  failure(function() return nil, "decoder rejected" end, "", "decoder rejected")
  failure(function() return {} end, "", "empty")
end)

T.test("argv launch preserves shell metacharacters/stdin EOF, cwd and separate stderr", function()
  local prompt = "'quotes' \"double\"\n$HOME $(touch SHOULD_NOT_RUN); & | > < `echo no`\r\nα😀\0end"
  local args = { "two words", "$(echo unsafe)", ";exit 9" }
  local cwd = vim.fn.getcwd() .. "/tests"
  local state = start("identity", function(stdout, stderr, status)
    T.eq("stderr only\r\n", stderr); T.eq(0, status); T.eq(false, vim.in_fast_event())
    return stdout
  end, nil, prompt, cwd, args)
  local value, err = wait(state)
  T.eq(nil, err)
  T.eq({ stdin = prompt, argv = args, cwd = cwd }, vim.json.decode(value))
end)

T.test("full stdin is streamed without a transport budget or trailing newline changes", function()
  local prompt = string.rep("α\r\n$; ", 50000) .. "EOF"
  local value, err = wait(start("eof", "plain", nil, prompt))
  T.eq(nil, err); T.eq(prompt, value)
end)

T.test("fake process split/coalesced event writes decode only completed final answers", function()
  for _, output in ipairs({ "opencode", "codex", "plain" }) do
    local value, err = wait(start(output, output))
    T.eq(nil, err); T.eq(answer, value)
  end
end)

T.test("fake process failure after partial text never falls back to a provider", function()
  spy(function(calls)
    for _, mode in ipairs({ "opencode-error", "codex-error", "nonzero" }) do
      local output = mode:match("^opencode") and "opencode" or mode:match("^codex") and "codex" or "plain"
      local value, err = wait(start(mode, output))
      T.eq(nil, value)
      assert(err:find(mode == "opencode-error" and "usage limit" or "authentication", 1, true), err)
    end
    T.eq(3, #calls)
  end)
end)

T.test("empty and interrupted processes are errors", function()
  for _, mode in ipairs({ "empty", "interrupted" }) do
    local value, err = wait(start(mode))
    T.eq(nil, value); assert(err:find(mode == "empty" and "empty" or "interrupted", 1, true), err)
  end
end)

T.test("missing executable returns nil,error and schedules its error exactly once", function()
  local count, callback_err = 0, nil
  local invocation, err = agent.run("prompt", { command = { "/no/such/irrelevant_explainer-fixture" } }, nil, function(value, failure_err)
    T.eq(nil, value); T.eq(false, vim.in_fast_event())
    count, callback_err = count + 1, failure_err
  end)
  T.eq(nil, invocation); assert(err:find("could not start", 1, true)); T.eq(0, count)
  assert(vim.wait(1000, function() return count == 1 end, 5))
  T.eq(err, callback_err)
  vim.wait(30, function() return false end, 5); T.eq(1, count)
end)

T.test("invalid command/config rejects without spawning", function()
  for _, config in ipairs({ { command = {} }, { command = "shell" }, { command = { fixture, 1 } },
    { command = { fixture }, timeout_ms = -1 }, { command = { fixture }, output = "unknown" } }) do
    local count = 0
    local invocation, err = agent.run("prompt", config, nil, function(value, callback_err)
      T.eq(nil, value); assert(callback_err); count = count + 1
    end)
    T.eq(nil, invocation); assert(err)
    assert(vim.wait(1000, function() return count == 1 end, 5))
  end
end)

T.test("timeout is asynchronous, stops owned process and suppresses late success", function()
  spy(function(calls, _, exits)
    local responsive = false
    vim.defer_fn(function() responsive = true end, 10)
    local state = start("slow", "plain", 100)
    assert(vim.wait(70, function() return responsive end, 5))
    T.eq(0, state.count)
    local value, err = wait(state)
    T.eq(nil, value); assert(err:find("timed out", 1, true))
    assert(vim.wait(1000, function() return #exits == 1 end, 5))
    T.eq(9, exits[1].signal)
    state.invocation.cancel()
    vim.wait(450, function() return false end, 5)
    T.eq(1, state.count); T.eq(1, #calls)
  end)
end)

T.test("cancel is idempotent, reports once on main thread and kills only owned invocation", function()
  spy(function(calls, _, exits)
    local state = start("slow")
    vim.wait(50, function() return false end, 5)
    local other = start("plain")
    state.invocation.cancel(); state.invocation.cancel()
    T.eq(0, state.count)
    local value, err = wait(state)
    T.eq(nil, value); T.eq("agent cancelled", err)
    T.eq(answer, wait(other))
    assert(vim.wait(1000, function() return #exits == 2 end, 5))
    local signals = { exits[1].signal, exits[2].signal }; table.sort(signals)
    T.eq({ 0, 9 }, signals)
    vim.wait(450, function() return false end, 5)
    T.eq(1, state.count); T.eq(1, other.count); T.eq(2, #calls)
  end)
end)

T.test("cancel between process completion and scheduled delivery overrides queued success", function()
  local original = vim.system
  vim.system = function(_, options, callback)
    options.stdout(nil, answer)
    callback({ code = 0, signal = 0 })
    return { kill = function() end }
  end
  local state
  local ok, err = xpcall(function()
    state = start("plain")
    state.invocation.cancel()
    local value, failure_err = wait(state)
    T.eq(nil, value); T.eq("agent cancelled", failure_err)
  end, debug.traceback)
  vim.system = original
  assert(ok, err)
end)

T.test("all decoders preserve assembled internal v2 output without interpreting schemas", function()
  local model = require("irrelevant_explainer.model")
  local snapshot = { mode = "diff", target = { scope = "review", files = {
    { scope = "file", file_id = "a", anchors = {} },
  } }, files = {}, comparison = { manifest = { { file_id = "a" } } } }
  local payload = { version = 2, review = { title = "Review", sections = {
    { heading = "Effects", detail = "Unknown rationale.", intent_basis = "unknown", evidence = {}, file_ids = { "a" } },
  } }, files = { { file_id = "a", notes = {} } } }
  local final = vim.json.encode(payload)
  local custom = function(stdout) return stdout end
  for _, decoder in ipairs({ "plain", "opencode", "codex", custom }) do
    local function encode(value)
      if decoder == "opencode" then
        local middle = math.floor(#value / 2)
        return wire({ text("early", "p", answer), text("final", "a", value:sub(1, middle)),
          text("final", "b", value:sub(middle + 1)) })
      elseif decoder == "codex" then
        return wire({ item("item.completed", answer), item("item.completed", value), { type = "turn.completed" } })
      end
      return value
    end
    local decoded = assert(agent.decode(decoder, encode(final), "", 0))
    T.eq(final, decoded); T.eq(payload, assert(model.validate(decoded, snapshot)))
    failure(decoder, encode(final), "status 2", 2)
    local truncated = assert(agent.decode(decoder, encode(final:sub(1, -8)), "", 0))
    T.eq(nil, model.validate(truncated, snapshot))
    local legacy = assert(agent.decode(decoder, encode(answer), "", 0))
    T.eq(nil, model.validate(legacy, snapshot))
  end
  failure("opencode", wire({ text("final", "a", final, false) }), "completed final")
  failure("opencode", wire({ text("final", "a", final), { type = "error", error = { message = "output limit" } } }), "output limit")
  failure("codex", wire({ item("item.completed", final) }), "completed final turn")
  failure("codex", wire({ item("item.completed", final), { type = "turn.failed", error = { message = "output limit" } } }), "output limit")
  failure(function() return nil, "output limit" end, final, "output limit")
end)

T.test("offline v3 phases survive all transports and reject nonzero, errors and truncation", function()
  local model, review, prompt = require("irrelevant_explainer.model"), require("irrelevant_explainer.review"), require("irrelevant_explainer.prompt")
  local anchor = { path = "a.lua", side = "new", start_line = 1, end_line = 1 }
  local target = { scope = "file", file_id = "a", anchors = { anchor } }
  local snapshot = { mode = "diff", target = { scope = "review", files = { target } },
    files = { { path = "a.lua", side = "new", lines = { "return true" } } },
    comparison = { manifest = { { file_id = "a", path = "a.lua", status = "A" } } } }
  local job = assert(review.create(snapshot, {}))
  local annotation = review.inspect(job).annotations[1].request
  local custom = function(stdout, stderr, status)
    assert(status == 0 or stderr:find("authentication", 1, true))
    return stdout
  end
  spy(function(calls)
    for _, phase in ipairs({ "annotate", "reduce", "synthesize" }) do
      local request = vim.deepcopy(annotation)
      request.phase = phase
      request.child_ids = { "child-a", "child-b" }
      local input = assert(prompt.review(request, 65536))
      local final
      for _, decoder in ipairs({ "plain", "opencode", "codex", custom }) do
        local mode = type(decoder) == "function" and "plain" or decoder
        local value, err = wait(start("whole-review-" .. mode, decoder, nil, input))
        T.eq(nil, err)
        local accepted = assert(model.validate_review(value, request))
        T.eq(3, accepted.version); T.eq(phase, accepted.phase)
        T.eq(request.request_id, accepted.request_id); T.eq(request.snapshot_id, accepted.snapshot_id)
        if phase == "annotate" then T.eq(#request.units, #accepted.units)
        else T.eq(request.child_ids, accepted.child_ids) end
        final = value
        failure(decoder, mode == "opencode" and wire({ text("final", "a", value) })
          or mode == "codex" and wire({ item("item.completed", value), { type = "turn.completed" } })
          or value, "status 7", 7)
        local truncated = value:sub(1, -8)
        local encoded = mode == "opencode" and wire({ text("final", "a", truncated) })
          or mode == "codex" and wire({ item("item.completed", truncated), { type = "turn.completed" } })
          or truncated
        T.eq(nil, model.validate_review(assert(agent.decode(decoder, encoded, "", 0)), request))
      end
      for _, mode in ipairs({ "opencode-error", "codex-error", "nonzero" }) do
        local decoder = mode:match("^opencode") and "opencode" or mode:match("^codex") and "codex" or "plain"
        local value, err = wait(start("whole-review-" .. mode, decoder, nil, input))
        T.eq(nil, value); assert(err:find(mode == "opencode-error" and "usage limit" or "authentication", 1, true), err)
      end
      local value, err = wait(start("whole-review-truncated", "plain", nil, input))
      T.eq(nil, err); T.eq(nil, model.validate_review(value, request))
      failure("opencode", wire({ text("final", "a", final, false) }), "completed final")
      failure("codex", wire({ item("item.completed", final) }), "completed final turn")
      failure(function() return nil, "output limit" end, final, "output limit")
      T.eq(nil, model.validate_review('{"version":2,"files":[]}', request))
    end
    T.eq(24, #calls) -- no repair, fallback, or paid provider process
  end)
end)
