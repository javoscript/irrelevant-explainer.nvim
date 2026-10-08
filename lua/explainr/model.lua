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
    assert(next_line > value.end_line, string.format("range includes unsent context lines: %s %s:%d-%d; first unsent line %d",
      value.path, value.side, value.start_line, value.end_line, next_line))
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
        assert(section.anchors == nil, "narrative sections must not have anchors")
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

local function fields(value, names)
  assert(type(value) == "table", "expected object")
  local allowed = {}
  for name in names:gmatch("%S+") do allowed[name] = true end
  for name in pairs(value) do assert(allowed[name], "unexpected field: " .. tostring(name)) end
end

local function limited_text(value, name, bytes)
  text(value, name)
  assert(#value <= bytes, name .. " exceeds " .. bytes .. " bytes")
end

local function acknowledgements(actual, expected, name)
  array(actual, name)
  local wanted, seen = {}, {}
  for _, id in ipairs(expected) do wanted[id] = true end
  for _, id in ipairs(actual) do
    assert(type(id) == "string" and wanted[id], "unknown " .. name)
    assert(not seen[id], "duplicate " .. name)
    seen[id] = true
  end
  for _, id in ipairs(expected) do assert(seen[id], "missing " .. name .. ": " .. id) end
end

-- Validate against precisely the transmitted request, not the frozen job. Version
-- 2 remains an INTERNAL assembly shape accepted by validate(), never a wire phase.
function M.validate_review(raw, request)
  local ok, result = pcall(function()
    local limits = request.output_limits
    local encoded = type(raw) == "string" and raw or vim.json.encode(raw)
    assert(#encoded <= limits.response_bytes, "response is " .. #encoded .. " bytes; response_max_bytes is " .. limits.response_bytes)
    local value = type(raw) == "string" and vim.json.decode(raw) or vim.deepcopy(raw)
    assert(type(value) == "table" and value.version == 3, "expected version 3 review response")
    for _, key in ipairs({ "phase", "request_id", "snapshot_id" }) do
      assert(value[key] == request[key], "wrong review " .. key)
    end
    local view = { mode = "diff", target = { scope = "review", files = {} },
      files = request.files, comparison = { manifest = request.manifest } }
    local function citations(item)
      array(item.evidence, "evidence")
      assert(#item.evidence <= limits.evidence_per_item, "too many evidence citations")
      for _, citation in ipairs(item.evidence) do fields(citation, "path side start_line end_line") end
    end
    local function section(item)
      citations(item)
      array(item.file_ids, "file_ids")
      assert(#item.file_ids <= limits.file_ids_per_item, "too many file_ids")
      local valid, err = M.validate({ version = 2, review = { title = "validation", sections = { item } }, files = {} }, view)
      assert(valid, err)
    end
    local function findings(items, count)
      array(items, "findings")
      assert(#items <= count, "too many findings")
      for _, finding in ipairs(items) do
        fields(finding, "text intent_basis evidence file_ids")
        limited_text(finding.text, "finding.text", limits.finding_bytes)
        section({ heading = "finding", detail = finding.text, intent_basis = finding.intent_basis,
          evidence = finding.evidence, file_ids = finding.file_ids })
      end
    end
    if request.phase == "annotate" then
      fields(value, "version phase request_id snapshot_id units")
      array(value.units, "units")
      local expected, actual, units = {}, {}, {}
      for _, unit in ipairs(request.units) do expected[#expected + 1] = unit.unit_id; units[unit.unit_id] = unit end
      for _, entry in ipairs(value.units) do actual[#actual + 1] = entry.unit_id end
      acknowledgements(actual, expected, "unit_id")
      for _, entry in ipairs(value.units) do
        fields(entry, "unit_id notes findings")
        assert(#vim.json.encode(entry) <= limits.unit_bytes, "unit output exceeds allocated unit_bytes " .. limits.unit_bytes)
        array(entry.notes, "notes")
        assert(#entry.notes <= limits.notes_per_unit, "too many notes")
        for _, note in ipairs(entry.notes) do
          fields(note, "summary detail anchors intent_basis evidence kind")
          limited_text(note.summary, "summary", limits.summary_bytes)
          limited_text(note.detail, "detail", limits.detail_bytes)
          citations(note)
          array(note.anchors, "anchors")
          for _, anchor in ipairs(note.anchors) do fields(anchor, "path side start_line end_line") end
        end
        local valid, err = M.validate({ version = 1, notes = entry.notes },
          { mode = "diff", target = units[entry.unit_id].target, files = request.files })
        assert(valid, err)
        findings(entry.findings, limits.findings_per_unit)
      end
    else
      acknowledgements(value.child_ids, request.child_ids, "child_ids")
      if request.phase == "reduce" then
        fields(value, "version phase request_id snapshot_id child_ids findings")
        findings(value.findings, limits.findings)
      else
        assert(request.phase == "synthesize", "unsupported review phase")
        fields(value, "version phase request_id snapshot_id child_ids review")
        fields(value.review, "title sections")
        limited_text(value.review.title, "review.title", limits.title_bytes)
        assert(not value.review.title:find("[\r\n]"), "review.title must occupy one line")
        array(value.review.sections, "sections")
        assert(#value.review.sections > 0 and #value.review.sections <= limits.sections, "invalid section count")
        for _, item in ipairs(value.review.sections) do
          fields(item, "heading detail intent_basis evidence file_ids")
          limited_text(item.heading, "heading", limits.heading_bytes)
          limited_text(item.detail, "detail", limits.detail_bytes)
          section(item)
        end
      end
    end
    return value
  end)
  if ok then return result end
  return nil, "Invalid " .. tostring(request.phase) .. " response: " .. tostring(result)
end

return M
