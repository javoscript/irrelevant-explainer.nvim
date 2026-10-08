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
    if snapshot.target.scope == "review" then
      assert(type(value) == "table" and value.version == 2, "unsupported explanation version (expected 2 for review)")
      assert(type(value.review) == "table", "review must be an object")
      text(value.review.title, "review.title")
      assert(not value.review.title:find("[\r\n]"), "review.title must occupy one line")
      array(value.review.sections, "review.sections")
      assert(#value.review.sections > 0, "review.sections must not be empty")
      local manifest, targets, seen = {}, {}, {}
      for _, entry in ipairs(snapshot.comparison.manifest) do manifest[entry.file_id] = true end
      for _, target in ipairs(snapshot.target.files) do targets[target.file_id] = target end
      for _, section in ipairs(value.review.sections) do
        text(section.heading, "section.heading")
        assert(not section.heading:find("[\r\n]"), "section.heading must occupy one line")
        text(section.detail, "section.detail")
        assert(vim.tbl_contains({ "documented", "inferred", "unknown" }, section.intent_basis), "invalid section intent_basis")
        array(section.evidence, "section.evidence")
        assert(section.intent_basis ~= "documented" or #section.evidence > 0, "documented section requires evidence")
        for _, citation in ipairs(section.evidence) do range(citation, snapshot, false) end
        array(section.file_ids, "section.file_ids")
        local references = {}
        for _, id in ipairs(section.file_ids) do
          assert(type(id) == "string" and manifest[id], "unknown section file_id")
          assert(not references[id], "duplicate section file_id")
          references[id] = true
        end
      end
      array(value.files, "files")
      for _, entry in ipairs(value.files) do
        text(entry.file_id, "file_id")
        local target = targets[entry.file_id]
        assert(target, "unknown or ineligible file_id: " .. entry.file_id)
        assert(not seen[entry.file_id], "duplicate file_id: " .. entry.file_id)
        seen[entry.file_id] = true
        local valid, err = M.validate({ version = 1, notes = entry.notes },
          { mode = snapshot.mode, target = target, files = snapshot.files })
        assert(valid, entry.file_id .. ": " .. tostring(err))
      end
      for _, target in ipairs(snapshot.target.files) do
        assert(seen[target.file_id], "missing file coverage: " .. target.file_id)
      end
      return value
    end
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
  local guidance = snapshot.target.scope == "review"
    and " Reduce the explicit comparison or use file/hunk scope; no partial review was accepted." or ""
  return nil, "Invalid explanation: " .. tostring(result) .. guidance
end

return M
