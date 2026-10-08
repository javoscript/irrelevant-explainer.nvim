local M = {}
local identity = require("explainr.identity")
local prompt = require("explainr.prompt")
local model = require("explainr.model")
local defaults = { request_max_bytes = 65536, response_max_bytes = 32768,
  max_snapshot_bytes = 16777216, max_requests = 128 }
local jobs = setmetatable({}, { __mode = "k" })
local function copy(value) return vim.deepcopy(value) end
local function bytes(value) return #vim.json.encode(value) end
local function source_key(path, side) return side .. "\0" .. path end
local function positive(value, name)
  assert(type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0,
    name .. " must be a positive finite integer")
end
local function protect(fn, ...)
  local ok, value, err = pcall(fn, ...)
  if ok then return value, err end
  return nil, tostring(value)
end
local function decision(path)
  path = path:lower()
  return path:find("openspec/", 1, true) or path:find("adr", 1, true)
    or path:find("decision", 1, true) or path:find("requirement", 1, true)
end

-- Only comparison metadata belongs in a wire manifest. Source, capture handles,
-- patches and opening provenance never travel through this projection.
local function manifest_entry(entry)
  local result = {}
  for _, key in ipairs({ "file_id", "path", "oldpath", "old_path", "new_path", "status", "kind", "text_unavailable", "binary" }) do
    result[key] = entry[key]
  end
  for _, side in ipairs({ "old", "new" }) do
    if entry[side] then
      result[side] = {}
      for _, key in ipairs({ "path", "side", "present", "absent", "empty", "binary", "eol", "endofline", "mode", "line_count", "identity", "oid" }) do
        result[side][key] = entry[side][key]
      end
    end
  end
  return result
end

-- Merge adjacent/overlapping supplied ranges, never fill a gap. The same helper
-- rehydrates evidence from frozen originals at EVERY synthesis/reduction level.
local function excerpts(job, ranges)
  local grouped, keys, files = {}, {}, {}
  for _, range in ipairs(ranges) do
    local key = source_key(range.path, range.side)
    assert(job.sources[key], "missing required source version")
    if not grouped[key] then grouped[key] = {}; keys[#keys + 1] = key end
    grouped[key][#grouped[key] + 1] = range
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local source, intervals = job.sources[key], grouped[key]
    table.sort(intervals, function(a, b) return a.start_line < b.start_line end)
    local merged = {}
    for _, range in ipairs(intervals) do
      assert(range.start_line >= 1 and range.end_line <= #source.lines, "evidence outside frozen source")
      local last = merged[#merged]
      if last and range.start_line <= last[2] + 1 then last[2] = math.max(last[2], range.end_line)
      else merged[#merged + 1] = { range.start_line, range.end_line } end
    end
    local file = { path = source.path, side = source.side, chunks = {} }
    for _, interval in ipairs(merged) do
      local lines = {}
      for line = interval[1], interval[2] do lines[#lines + 1] = source.lines[line] end
      file.chunks[#file.chunks + 1] = { start_line = interval[1], lines = lines }
    end
    files[#files + 1] = file
  end
  return files
end

local function limits(job)
  local response = job.config.review.response_max_bytes
  local allocation = math.min(8192, response)
  return { response_bytes = response, unit_bytes = allocation,
    notes_per_unit = math.min(8, math.floor(allocation / 1024)),
    findings_per_unit = math.min(4, math.floor(allocation / 2048)),
    summary_bytes = math.min(256, allocation), detail_bytes = math.min(2048, math.max(1, math.floor(allocation / 8))),
    finding_bytes = math.min(1024, math.max(1, math.floor(allocation / 8))),
    evidence_per_item = 8, file_ids_per_item = 16, findings = math.min(16, math.floor(response / 2048)),
    sections = math.max(1, math.min(12, math.floor(response / 2048))), title_bytes = 256, heading_bytes = 256 }
end

local function request(job, phase, units, children, optional)
  local ranges, ids, findings, manifest, wanted = {}, {}, {}, {}, {}
  for _, unit in ipairs(units or {}) do
    wanted[unit.file_id] = true
    for _, range in ipairs(unit.target.anchors) do ranges[#ranges + 1] = range end
  end
  for _, target in ipairs(optional or {}) do
    wanted[target.file_id] = true
    for _, range in ipairs(target.anchors) do ranges[#ranges + 1] = range end
  end
  for _, child in ipairs(children or {}) do
    ids[#ids + 1] = child.id
    findings[#findings + 1] = { child_id = child.id, findings = child.findings }
    for _, finding in ipairs(child.findings) do
      for _, range in ipairs(finding.evidence) do ranges[#ranges + 1] = range end
    end
  end
  for _, entry in ipairs(job.manifest) do
    if phase ~= "annotate" or wanted[entry.file_id] then manifest[#manifest + 1] = entry end
  end
  local req = { version = 3, phase = phase, snapshot_id = job.id, output_limits = limits(job),
    files = excerpts(job, ranges), manifest = manifest, coverage = "Only the supplied chunks are visible; job-wide coverage is distributed." }
  if phase == "annotate" then req.units = units
  else req.child_ids, req.inputs = ids, findings end
  req.request_id = identity.hash(req)
  local text, err, size = prompt.review(req, job.input_cap)
  if phase ~= "annotate" then
    local minimum = { version = 3, phase = phase, snapshot_id = job.id, request_id = req.request_id, child_ids = ids }
    if phase == "reduce" then minimum.findings = {}
    else minimum.review = { title = "x", sections = { { heading = "x", detail = "x", intent_basis = "unknown", evidence = {}, file_ids = {} } } } end
    local required = bytes(minimum)
    if required > job.config.review.response_max_bytes then
      text, err = nil, phase .. " mandatory response acknowledgements require " .. required
        .. " bytes; response_max_bytes is " .. job.config.review.response_max_bytes
    end
  end
  return { request = req, prompt = text, error = err, bytes = size, children = children }
end

local function unit(job, target, anchors, whole)
  local hunks, indices = {}, {}
  for index, hunk in ipairs(target.hunks or {}) do
    for _, anchor in ipairs(anchors) do
      local pos = anchor.side == "old" and 1 or 3
      local first, count = hunk[pos], hunk[pos + 1]
      if (count > 0 and first <= anchor.end_line and first + count - 1 >= anchor.start_line)
        or (count == 0 and first >= anchor.start_line - 1 and first <= anchor.end_line) then
        hunks[#hunks + 1], indices[#indices + 1] = hunk, index
        break
      end
    end
  end
  local value = { file_id = target.file_id, whole_file = whole, fragment = not whole,
    hunk_indices = indices, target = { scope = whole and "file" or "hunk", file_id = target.file_id,
      path = target.path, anchors = anchors, hunks = hunks } }
  value.unit_id = identity.hash({ snapshot = job.id, unit = value })
  return value
end

local function fits(job, value) return request(job, "annotate", { value }).prompt ~= nil end

local function split(job, target)
  local result = {}
  local function add(anchors)
    if #anchors == 0 then return end
    local value = unit(job, target, anchors, false)
    if fits(job, value) then result[#result + 1] = value; return end
    -- An oversized paired hunk is fragmented independently on each side. Never
    -- invent paired old/new coordinates by dividing unequal lengths together.
    for _, anchor in ipairs(anchors) do
      local first = anchor.start_line
      while first <= anchor.end_line do
        local lo, hi, best = first, anchor.end_line, nil
        while lo <= hi do
          local last = math.floor((lo + hi) / 2)
          local part = copy(anchor); part.start_line, part.end_line = first, last
          local candidate = unit(job, target, { part }, false)
          if fits(job, candidate) then best = candidate; lo = last + 1 else hi = last - 1 end
        end
        assert(best, "annotate " .. target.file_id .. ": indivisible source line " .. first
          .. " plus mandatory overhead exceeds effective request_max_bytes " .. job.input_cap .. "; no source was truncated")
        result[#result + 1] = best
        first = best.target.anchors[1].end_line + 1
      end
    end
  end
  -- Prefer real hunk boundaries and keep changed pairs together when affordable.
  local cursors = {}
  for _, anchor in ipairs(target.anchors) do cursors[anchor.side] = 1 end
  for _, hunk in ipairs(target.hunks or {}) do
    local before, changed = {}, {}
    for _, anchor in ipairs(target.anchors) do
      local pos = anchor.side == "old" and 1 or 3
      local first, count = hunk[pos], hunk[pos + 1]
      local start = count == 0 and first + 1 or first
      local cursor = cursors[anchor.side]
      if start > cursor then
        local part = copy(anchor); part.start_line, part.end_line = cursor, math.min(start - 1, anchor.end_line)
        if part.start_line <= part.end_line then before[#before + 1] = part end
      end
      if count > 0 then
        local part = copy(anchor); part.start_line, part.end_line = math.max(cursor, first), math.min(first + count - 1, anchor.end_line)
        if part.start_line <= part.end_line then changed[#changed + 1] = part end
      end
      cursors[anchor.side] = math.max(cursor, start + count)
    end
    add(before); add(changed)
  end
  local remaining = {}
  for _, anchor in ipairs(target.anchors) do
    local part = copy(anchor); part.start_line = cursors[anchor.side]
    if part.start_line <= part.end_line then remaining[#remaining + 1] = part end
  end
  add(remaining)
  return result
end

local function coverage(job)
  local owned, expected, seen, owners = {}, {}, {}, {}
  for _, target in ipairs(job.targets) do
    assert(not seen[target.file_id], "duplicate target file_id"); seen[target.file_id] = true
    for _, anchor in ipairs(target.anchors) do
      local key = source_key(anchor.path, anchor.side)
      local source = job.sources[key]
      assert(source and source.lines and #source.lines > 0, "missing required version for " .. target.file_id)
      assert(anchor.start_line == 1 and anchor.end_line == #source.lines, "review requires complete whole-file anchors")
      assert(not expected[key], "duplicate target source ownership")
      expected[key] = #source.lines
      owners[key] = target.file_id
    end
  end
  local unit_ids = {}
  for _, value in ipairs(job.units) do
    assert(not unit_ids[value.unit_id], "duplicate unit_id"); unit_ids[value.unit_id] = true
    assert(seen[value.file_id] and #value.target.anchors > 0, "unknown or empty annotation unit")
    for _, anchor in ipairs(value.target.anchors) do
      local key = source_key(anchor.path, anchor.side)
      assert(expected[key] and owners[key] == value.file_id, "unit owns ineligible or another file's source")
      owned[key] = owned[key] or {}; owned[key][#owned[key] + 1] = anchor
    end
  end
  for key, count in pairs(expected) do
    local ranges = owned[key] or {}
    table.sort(ranges, function(a, b) return a.start_line < b.start_line end)
    local next_line = 1
    for _, range in ipairs(ranges) do
      assert(range.start_line == next_line and range.end_line >= next_line, "unit coverage gap or overlap")
      next_line = range.end_line + 1
    end
    assert(next_line == count + 1, "missing unit coverage")
  end
end

local function plan(job)
  job.units, job.annotations = {}, {}
  for _, target in ipairs(job.targets) do
    assert(#target.anchors > 0, "empty annotation target")
    local whole = unit(job, target, target.anchors, true)
    local values = fits(job, whole) and { whole } or split(job, target)
    for _, value in ipairs(values) do job.units[#job.units + 1] = value end
  end
  coverage(job)
  local output = job.config.review.response_max_bytes
  local capacity = math.max(1, math.floor((output - 512) / 8192))
  local batch = {}
  local function flush()
    if #batch == 0 then return end
    local optional, assigned = {}, {}
    for _, value in ipairs(batch) do assigned[value.file_id] = true end
    local built = request(job, "annotate", batch)
    assert(built.prompt, built.error)
    for _, target in ipairs(job.targets) do
      if not assigned[target.file_id] and decision(target.path or target.anchors[1].path) then
        optional[#optional + 1] = target
        local candidate = request(job, "annotate", batch, nil, optional)
        if candidate.prompt then built = candidate else optional[#optional] = nil end
      end
    end
    local minimum = { version = 3, phase = "annotate", request_id = built.request.request_id, snapshot_id = job.id, units = {} }
    for _, value in ipairs(batch) do minimum.units[#minimum.units + 1] = { unit_id = value.unit_id, notes = {}, findings = {} } end
    assert(bytes(minimum) <= output, "annotate mandatory acknowledgements exceed response_max_bytes " .. output)
    job.annotations[#job.annotations + 1] = built
    batch = {}
  end
  for _, value in ipairs(job.units) do
    local candidate = copy(batch); candidate[#candidate + 1] = value
    if #candidate > capacity or not request(job, "annotate", candidate).prompt then flush() end
    batch[#batch + 1] = value
  end
  flush()
end

function M.create(snapshot, config, previous)
  return protect(function()
    assert(snapshot.mode == "diff" and snapshot.target.scope == "review", "review requires a full diff review snapshot")
    local captured = copy(config or {})
    captured.review = vim.tbl_extend("force", defaults, captured.review or {})
    captured.context = captured.context or {}; captured.context.max_bytes = captured.context.max_bytes or 262144
    captured.ai = captured.ai or {}
    for name in pairs(defaults) do positive(captured.review[name], "review." .. name) end
    positive(captured.context.max_bytes, "context.max_bytes")
    -- Stable across processes, even when a custom function decoder is used. Its
    -- same-process identity is checked separately by deep_equal below.
    local stable = copy(captured)
    if type(stable.ai.output) == "function" then
      stable.cache = stable.cache or {}; stable.cache.decoder_key = stable.cache.decoder_key or "memory-only"
    end
    local _, id = identity.key(snapshot, stable)
    local job = { snapshot = copy(snapshot), config = captured, id = id,
      input_cap = math.min(captured.context.max_bytes, captured.review.request_max_bytes),
      sources = {}, manifest = {}, targets = copy(snapshot.target.files), checkpoints = {} }
    for _, source in ipairs(job.snapshot.files) do
      if source.lines and #source.lines > 0 and not source.empty and not source.binary then
        local key = source_key(source.path, source.side)
        assert(not job.sources[key], "duplicate source version")
        job.sources[key] = source
      end
    end
    local ids = {}
    for _, entry in ipairs(snapshot.comparison.manifest) do
      assert(type(entry.file_id) == "string" and not ids[entry.file_id], "invalid manifest file_id")
      ids[entry.file_id] = entry
      job.manifest[#job.manifest + 1] = manifest_entry(entry)
    end
    table.sort(job.manifest, function(a, b) return a.file_id < b.file_id end)
    assert(#job.targets > 0, "review has no eligible text targets")
    for _, target in ipairs(job.targets) do
      local entry = ids[target.file_id]
      assert(entry, "target absent from manifest")
      assert(not entry.binary and not entry.text_unavailable, "metadata-only entry cannot own annotation units")
    end
    table.sort(job.targets, function(a, b)
      local ap, bp = a.path or a.anchors[1].path, b.path or b.anchors[1].path
      local ad, bd = not not decision(ap), not not decision(bp)
      if ad ~= bd then return ad end
      if ap ~= bp then return ap < bp end
      return a.file_id < b.file_id
    end)
    plan(job) -- ALL annotations admitted before any process can start.
    local old = previous and jobs[previous]
    if old and old.id == id and vim.deep_equal(old.config, captured) then job.checkpoints = copy(old.checkpoints) end
    local handle = {}; jobs[handle] = job
    return handle
  end)
end

local function packet(job, children)
  local findings, ranges = {}, {}
  for _, child in ipairs(children) do
    for _, finding in ipairs(child.findings) do
      findings[#findings + 1] = finding
      for _, citation in ipairs(finding.evidence) do ranges[#ranges + 1] = citation end
    end
  end
  return { findings = findings, files = excerpts(job, ranges) }
end

local function machine(job)
  return { annotation = 1, children = {}, notes = {}, completed = 0, outputs = {}, job = job }
end

local function next_request(state)
  local job = state.job
  if state.annotation <= #job.annotations then state.phase = "annotate"; return job.annotations[state.annotation] end
  if state.final then return nil end
  if state.groups then return state.groups[state.group] end
  state.phase = "synthesize"
  local final = request(job, "synthesize", nil, state.children)
  if final.prompt then return final end
  -- Even no findings cannot rescue an oversized complete manifest/coverage.
  local empty = request(job, "synthesize", nil, {})
  assert(empty.prompt, "synthesize manifest/mandatory overhead: " .. tostring(empty.error))
  state.phase = "reduce"
  local groups, batch = {}, {}
  local function flush()
    if #batch == 0 then return end
    local built = request(job, "reduce", nil, batch)
    assert(built.prompt, "reduce indivisible finding/evidence packet: " .. tostring(built.error))
    groups[#groups + 1] = built; batch = {}
  end
  for _, child in ipairs(state.children) do
    local candidate = copy(batch); candidate[#candidate + 1] = child
    if not request(job, "reduce", nil, candidate).prompt then flush() end
    batch[#batch + 1] = child
  end
  flush()
  assert(#groups > 0, "synthesize cannot fit an empty evidence packet")
  state.level_bytes = bytes(packet(job, state.children))
  state.groups, state.group, state.reduced = groups, 1, {}
  return groups[1]
end

local function accept(state, built, output)
  local req, job = built.request, state.job
  local value, err = model.validate_review(output, req)
  assert(value, err)
  if req.phase == "annotate" then
    local by_id, findings = {}, {}
    for _, entry in ipairs(value.units) do by_id[entry.unit_id] = entry end
    for _, unit in ipairs(req.units) do
      local entry = by_id[unit.unit_id]
      state.notes[unit.unit_id] = entry.notes
      for _, finding in ipairs(entry.findings) do findings[#findings + 1] = finding end
    end
    state.children[#state.children + 1] = { id = req.request_id, findings = findings }
    state.completed = state.completed + #req.units
    state.annotation = state.annotation + 1
  elseif req.phase == "reduce" then
    local child = { id = req.request_id, findings = value.findings }
    local before, after = bytes(packet(job, built.children)), bytes(packet(job, { child }))
    assert(after < before, "reduce nonprogress: findings/evidence " .. before .. " -> " .. after .. " bytes (must strictly decrease)")
    local reduced = copy(state.reduced); reduced[#reduced + 1] = child
    if state.group == #state.groups then
      local level_bytes = bytes(packet(job, reduced))
      assert(level_bytes < state.level_bytes, "reduce level nonprogress: shared findings/evidence "
        .. state.level_bytes .. " -> " .. level_bytes .. " bytes (must strictly decrease)")
    end
    state.reduced = reduced
    state.group = state.group + 1
    if state.group > #state.groups then state.children, state.groups = state.reduced, nil end
  else state.final = value.review end
  state.outputs[#state.outputs + 1] = value
  return value
end

local function assemble(state)
  assert(state.final and state.completed == #state.job.units, "incomplete review coverage")
  local files, by_file, seen = {}, {}, {}
  for _, target in ipairs(state.job.snapshot.target.files) do
    local entry = { file_id = target.file_id, notes = {} }
    files[#files + 1] = entry; by_file[target.file_id], seen[target.file_id] = entry, {}
  end
  for _, unit in ipairs(state.job.units) do
    assert(state.notes[unit.unit_id], "missing unit result")
    for _, note in ipairs(state.notes[unit.unit_id]) do
      local key = identity.canonical(note)
      if not seen[unit.file_id][key] then
        seen[unit.file_id][key] = true
        local notes = by_file[unit.file_id].notes; notes[#notes + 1] = note
      end
    end
  end
  local result, err = model.validate({ version = 2, review = state.final, files = files }, state.job.snapshot)
  assert(result, err)
  return result
end

local function diagnostic(state, built, err)
  return string.format("Review %s %s (%d/%d units; request %s bytes, input cap %d, response cap %d): %s. "
    .. "Use :Explainr review in the owning comparison or reader to resume; :ExplainrRefresh in Review regenerates. "
    .. "Reduce review limits or scope for provider context/compaction/output failures; byte guardrails are not provider token guarantees.",
    built and built.request.phase or state.phase or "planning", built and built.request.request_id:sub(1, 12) or "",
    state.completed, #state.job.units, built and built.bytes or "unknown", state.job.input_cap,
    state.job.config.review.response_max_bytes, tostring(err):sub(1, 2048))
end

function M.start(handle, callbacks)
  local job = assert(jobs[handle], "invalid review job")
  if job.operation then job.operation.cancel() end
  local state, active, calls, stopped = machine(job), nil, 0, false
  local operation = {}
  function operation.cancel()
    if stopped then return end
    stopped = true
    if job.operation == operation then job.operation = nil end
    if active then active.cancel() end
  end
  job.operation = operation
  local function finish(result, err, record)
    if stopped then return end
    stopped = true; job.operation = nil
    callbacks.complete(result, err, record)
  end
  local function annotation_progress()
    return "Annotating " .. math.floor(state.completed * 100 / #job.units) .. "%"
  end
  local function fresh(continuation)
    if stopped then return end
    local called = false
    callbacks.fresh(function(valid)
      if stopped or called then return end
      called = true
      if not valid then
        job.checkpoints = {}
        finish(nil, diagnostic(state, nil, "snapshot or ownership is stale"))
      else continuation() end
    end)
  end
  local step
  local function schedule() vim.schedule(function() if not stopped then step() end end) end
  step = function()
    local built, err = protect(next_request, state)
    if err then finish(nil, diagnostic(state, nil, err)); return end
    if not built then
      local result, invalid = protect(assemble, state)
      if not result then finish(nil, diagnostic(state, nil, invalid)); return end
      fresh(function()
        finish(copy(result), nil, { version = 1, snapshot_id = job.id, outputs = copy(state.outputs) })
      end)
      return
    end
    local phase = built.request.phase
    callbacks.progress(phase == "annotate" and annotation_progress()
      or phase == "reduce" and "reducing" or "synthesizing")
    if stopped then return end
    local checkpoint = job.checkpoints[built.request.request_id]
    if checkpoint then
      local accepted, invalid = protect(accept, state, built, checkpoint)
      if not accepted then finish(nil, diagnostic(state, built, invalid)) else schedule() end
      return
    end
    if calls >= job.config.review.max_requests then
      finish(nil, diagnostic(state, built, "max_requests " .. job.config.review.max_requests .. " exhausted after " .. calls .. " launches")); return
    end
    calls = calls + 1
    local delivered = false
    active = require("explainr.agent").run(built.prompt, job.config.ai, job.snapshot.cwd, function(raw, failure)
      if stopped or delivered then return end
      delivered = true; active = nil
      if failure then finish(nil, diagnostic(state, built, failure)); return end
      -- Validate without mutating the state until freshness has also succeeded.
      local validated, invalid = model.validate_review(raw, built.request)
      if not validated then finish(nil, diagnostic(state, built, invalid)); return end
      fresh(function()
        local accepted, accept_error = protect(accept, state, built, validated)
        if not accepted then finish(nil, diagnostic(state, built, accept_error)); return end
        job.checkpoints[built.request.request_id] = copy(accepted)
        if phase == "annotate" then callbacks.progress(annotation_progress()) end
        schedule()
      end)
    end)
  end
  callbacks.progress("Pending · planning")
  vim.schedule(function() fresh(schedule) end)
  return operation
end

-- Completed records contain only validated result/provenance data. Replay
-- reconstructs every request and original evidence, with no processes or async.
function M.validate_record(record, snapshot, config)
  return protect(function()
    assert(type(record) == "table" and record.version == 1 and type(record.outputs) == "table"
      and vim.islist(record.outputs), "invalid completed review record")
    for key in pairs(record) do assert(key == "version" or key == "snapshot_id" or key == "outputs", "unexpected record field") end
    local handle, err = M.create(snapshot, config)
    assert(handle, err)
    local job = jobs[handle]
    assert(record.snapshot_id == job.id, "completed review fingerprint mismatch")
    local state = machine(job)
    for _, output in ipairs(record.outputs) do
      local built = next_request(state)
      assert(built, "extra completed review output")
      accept(state, built, output)
    end
    assert(state.final, "incomplete completed review record")
    return assemble(state)
  end)
end

-- Read-only copies for session freshness checks and focused planner tests. The
-- opaque handle prevents accidental mutation of frozen evidence/checkpoints.
function M.snapshot(handle) return copy(assert(jobs[handle]).snapshot) end
function M.config(handle) return copy(assert(jobs[handle]).config) end
function M.inspect(handle)
  local job = assert(jobs[handle])
  return copy({ snapshot_id = job.id, units = job.units, annotations = job.annotations, checkpoints = job.checkpoints })
end
function M.validate_coverage(handle, units)
  return protect(function()
    local job = setmetatable({ units = units }, { __index = assert(jobs[handle]) })
    coverage(job); return true
  end)
end

return M
