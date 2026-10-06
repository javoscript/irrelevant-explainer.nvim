local M = {}

local function array(value, name)
  assert(type(value) == "table" and vim.islist(value), name .. " must be an array")
end

local function text(value, name)
  assert(type(value) == "string" and value:find("%S"), name .. " must be nonempty text")
end

local function contains(outer, inner)
  return outer.path == inner.path and outer.side == inner.side
    and inner.start_line >= outer.start_line and inner.end_line <= outer.end_line
end

local function range(value, snapshot, target)
  assert(type(value) == "table", "range must be an object")
  text(value.path, "range.path")
  assert(vim.tbl_contains({ "buffer", "old", "new" }, value.side), "unsupported range.side")
  for _, key in ipairs({ "start_line", "end_line" }) do
    assert(type(value[key]) == "number" and value[key] % 1 == 0 and value[key] >= 1, key .. " must be a positive integer")
  end
  assert(value.end_line >= value.start_line, "range ends before it starts")
  local file
  for _, item in ipairs(snapshot.files) do
    if item.path == value.path and item.side == value.side then file = item; break end
  end
  assert(file and not file.empty, "range is absent from supplied context")
  if file.chunks then
    -- Compact excerpts retain source coordinates without placeholder arrays.
    -- Every line must be covered, even when a citation crosses chunk boundaries.
    local next_line = value.start_line
    for _, chunk in ipairs(file.chunks) do
      local last = chunk.start_line + #chunk.lines - 1
      if chunk.start_line <= next_line and last >= next_line then next_line = last + 1 end
      if next_line > value.end_line then break end
    end
    assert(next_line > value.end_line, "range includes unsent context lines")
  else
    assert(file.lines and value.end_line <= #file.lines, "range is absent from supplied context")
  end
  if file.included then
    for line = value.start_line, value.end_line do
      assert(file.included[line], "range includes unsent context lines")
    end
  end
  if target then
    local valid = false
    for _, allowed in ipairs(snapshot.target.anchors) do
      if contains(allowed, value) then valid = true; break end
    end
    assert(valid, "anchor is outside the focused target")
  end
end

function M.validate(raw, snapshot)
  local ok, result = pcall(function()
    local value = type(raw) == "string" and vim.json.decode(raw) or raw
    assert(type(value) == "table" and value.version == 1, "unsupported explanation version (expected 1)")
    array(value.notes, "notes")
    local overview = false
    for _, note in ipairs(value.notes) do
      text(note.summary, "summary")
      assert(not note.summary:find("[\r\n]"), "summary must occupy one line")
      text(note.detail, "detail")
      array(note.anchors, "anchors")
      assert(#note.anchors >= 1 and #note.anchors <= (snapshot.mode == "code" and 1 or 2), "invalid anchor count")
      local sides = {}
      for _, anchor in ipairs(note.anchors) do
        range(anchor, snapshot, true)
        assert(not sides[anchor.side], "duplicate anchor side")
        assert(snapshot.mode ~= "code" or anchor.side == "buffer", "code notes require buffer anchors")
        assert(snapshot.mode ~= "diff" or anchor.side ~= "buffer", "diff notes require old/new anchors")
        sides[anchor.side] = true
      end
      if note.kind ~= nil then
        assert(note.kind == "overview" and snapshot.target.scope == "file", "overview notes require file scope")
        assert(not overview, "only one file overview is allowed")
        overview = true
        assert(#note.anchors == #snapshot.target.anchors, "overview must cover all whole-file target anchors")
        for _, anchor in ipairs(note.anchors) do
          local complete = false
          for _, allowed in ipairs(snapshot.target.anchors) do
            if contains(anchor, allowed) and contains(allowed, anchor) then complete = true; break end
          end
          assert(complete, "overview must cover all whole-file target anchors")
        end
      end
      assert(vim.tbl_contains({ "documented", "inferred", "unknown" }, note.intent_basis), "invalid intent_basis")
      array(note.evidence, "evidence")
      assert(note.intent_basis ~= "documented" or #note.evidence > 0, "documented intent requires evidence")
      for _, citation in ipairs(note.evidence) do range(citation, snapshot, false) end
    end
    return value
  end)
  if ok then return result end
  return nil, "Invalid explanation: " .. tostring(result)
end

return M
