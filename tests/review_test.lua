local review = require("explainr.review")
local model = require("explainr.model")

T.test("setup validates review and persistent cache limits without changing prior configuration", function()
  local plugin = require("explainr")
  local saved = vim.deepcopy(plugin.config)
  plugin.setup()
  T.eq({ request_max_bytes = 65536, response_max_bytes = 32768, max_snapshot_bytes = 16777216,
    max_requests = 128 }, plugin.config.review)
  T.eq({ enabled = true, max_bytes = 104857600, namespace = "default" }, plugin.config.cache)
  for _, group in ipairs({ "review", "cache" }) do
    local keys = group == "review" and { "request_max_bytes", "response_max_bytes", "max_snapshot_bytes", "max_requests" }
      or { "max_bytes" }
    for _, key in ipairs(keys) do
      for _, value in ipairs({ 0, -1, 0.5, math.huge, "100", false }) do
        local ok, err = pcall(plugin.setup, { [group] = { [key] = value } })
        assert(not ok and err:find(group .. "." .. key, 1, true), tostring(err))
      end
    end
  end
  for _, options in ipairs({ { enabled = "yes" }, { namespace = "" }, { namespace = 1 },
    { decoder_key = "" }, { decoder_key = false } }) do
    T.eq(false, pcall(plugin.setup, { cache = options }))
  end
  T.eq(65536, plugin.config.review.request_max_bytes)
  plugin.setup(saved)
end)

local function range(path, side, first, last)
  return { path = path, side = side, start_line = first, end_line = last or first }
end
local function fixture(count, line_count, width)
  local snapshot = { mode = "diff", cwd = vim.fn.getcwd(), target = { scope = "review", files = {} },
    files = {}, comparison = { identities = { old = "base", new = "working" }, manifest = {} }, context = { strategy = "review" } }
  for i = 1, count or 1 do
    local path, id, lines = string.format("src/file%03d.lua", i), "file" .. i, {}
    for n = 1, line_count or 3 do lines[n] = "é中 " .. n .. string.rep("x", width or 0) end
    snapshot.files[#snapshot.files + 1] = { path = path, side = "new", lines = lines }
    snapshot.target.files[#snapshot.target.files + 1] = { scope = "file", file_id = id, path = path,
      anchors = { range(path, "new", 1, #lines) }, hunks = { { 0, 0, 1, #lines } } }
    snapshot.comparison.manifest[#snapshot.comparison.manifest + 1] = { file_id = id, path = path,
      patch = "PATCH MUST NOT TRAVEL", old = { absent = true }, new = { path = path, side = "new", lines = lines } }
  end
  snapshot.comparison.manifest[#snapshot.comparison.manifest + 1] = { file_id = "binary", path = "image.png", text_unavailable = "binary" }
  snapshot.comparison.manifest[#snapshot.comparison.manifest + 1] = { file_id = "empty", path = "empty.txt", text_unavailable = "empty" }
  return snapshot
end
local function answer(req)
  local value = { version = 3, phase = req.phase, request_id = req.request_id, snapshot_id = req.snapshot_id }
  if req.phase == "annotate" then
    value.units = {}
    for _, unit in ipairs(req.units) do value.units[#value.units + 1] = { unit_id = unit.unit_id, notes = {}, findings = {} } end
  elseif req.phase == "reduce" then value.child_ids, value.findings = req.child_ids, {}
  else
    value.child_ids = req.child_ids
    value.review = { title = "Change", sections = { { heading = "Relationships", detail = "Distributed reasoning; intent is unknown.",
      intent_basis = "unknown", evidence = {}, file_ids = { "binary", "empty" } } } }
  end
  return value
end
local function run(job, respond, fresh)
  local agent = require("explainr.agent")
  local original = agent.run
  local calls, statuses, completion, running = {}, {}, nil, false
  agent.run = function(text, _, _, callback)
    assert(not running, "two simultaneous invocations"); running = true
    local req = vim.json.decode(assert(text:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)")))
    calls[#calls + 1] = { request = req, bytes = #text }
    local value, err = answer(req), nil
    if respond then value, err = respond(req, #calls, value) end
    vim.schedule(function() running = false; callback(value and vim.json.encode(value), err) end)
    return { cancel = function() running = false end }
  end
  local ok, err = xpcall(function()
    review.start(job, { progress = function(status) statuses[#statuses + 1] = status end,
      fresh = fresh or function(done) done(true) end,
      complete = function(result, failure, record) completion = { result = result, error = failure, record = record } end })
    assert(vim.wait(10000, function() return completion ~= nil end, 1), "review did not complete")
  end, debug.traceback)
  agent.run = original
  assert(ok, err)
  return completion, calls, statuses
end

T.test("review planner preserves asymmetric rename sides and split hunk coverage exactly", function()
  local s = fixture(1, 43, 100)
  local old = { path = "before.lua", side = "old", lines = {} }
  for n = 1, 19 do old.lines[n] = "old " .. n .. string.rep("y", 100) end
  s.files[#s.files + 1] = old
  table.insert(s.target.files[1].anchors, 1, range("before.lua", "old", 1, 19))
  s.target.files[1].hunks = { { 3, 4, 3, 9 }, { 12, 8, 20, 24 } }
  local job = assert(review.create(s, { context = { max_bytes = 5100 }, review = { request_max_bytes = 99999 } }))
  local plan = review.inspect(job)
  assert(#plan.units > 4)
  local owned = { old = {}, new = {} }
  for _, unit in ipairs(plan.units) do
    assert(unit.fragment and not unit.whole_file and unit.target.scope == "hunk")
    for _, anchor in ipairs(unit.target.anchors) do
      T.eq(anchor.side == "old" and "before.lua" or s.files[1].path, anchor.path)
      for n = anchor.start_line, anchor.end_line do
        assert(not owned[anchor.side][n]); owned[anchor.side][n] = true
      end
    end
  end
  for _, side in ipairs({ "old", "new" }) do
    local expected = {}; for n = 1, side == "old" and 19 or 43 do expected[n] = true end
    T.eq(expected, owned[side])
  end
  for _, invocation in ipairs(plan.annotations) do
    assert(invocation.bytes <= 5100)
    assert(not invocation.prompt:find("PATCH MUST NOT TRAVEL", 1, true))
    for _, file in ipairs(invocation.request.files) do
      assert(file.chunks and not file.lines)
      local original = file.side == "old" and old.lines or s.files[1].lines
      for _, chunk in ipairs(file.chunks) do
        T.eq(chunk.start_line + #chunk.lines - 1, chunk.end_line)
        T.eq(vim.list_slice(original, chunk.start_line, chunk.end_line), chunk.lines)
      end
    end
  end
  assert(review.validate_coverage(job, plan.units))
  table.remove(plan.units, 2); T.eq(nil, review.validate_coverage(job, plan.units))
  plan = review.inspect(job); plan.units[#plan.units + 1] = plan.units[1]
  T.eq(nil, review.validate_coverage(job, plan.units))
  local done = run(job); assert(done.result, done.error); T.eq(1, #done.result.files)
end)

T.test("whole files output packing missing sources empty comparison and indivisible lines preflight", function()
  local job = assert(review.create(fixture(11), {}))
  local plan = review.inspect(job)
  T.eq(11, #plan.units); T.eq(4, #plan.annotations)
  for _, batch in ipairs(plan.annotations) do
    assert(#batch.request.units <= 3)
    assert(batch.request.output_limits.unit_bytes >= 8192)
  end
  T.eq(nil, review.create(fixture(0), {}))
  local s = fixture(); s.files = {}
  T.eq(nil, review.create(s, {}))
  local bad, err = review.create(fixture(1, 1, 10000), { review = { request_max_bytes = 5000 } })
  T.eq(nil, bad); assert(err:find("indivisible", 1, true))
  T.eq(nil, review.create(fixture(), { review = { response_max_bytes = 1 } }))
  local small = assert(review.create(fixture(3), { review = { response_max_bytes = 4096 } }))
  T.eq(3, #review.inspect(small).annotations)
  for _, key in ipairs({ "request_max_bytes", "response_max_bytes", "max_snapshot_bytes", "max_requests" }) do
    for _, value in ipairs({ 0, -1, 1.1, math.huge, "100" }) do T.eq(nil, review.create(fixture(), { review = { [key] = value } })) end
  end
end)

T.test("annotation units share the available response budget including the envelope", function()
  for _, count in ipairs({ 1, 2, 3 }) do
    local s = fixture(count)
    local job = assert(review.create(s, {}))
    local req = review.inspect(job).annotations[1].request
    T.eq(count, #req.units)
    assert(req.output_limits.unit_bytes > 8192, "unused output space must be available to assigned units")
    local value = answer(req)
    for i, unit in ipairs(req.units) do
      for n = 1, 8 do
        value.units[i].notes[n] = { summary = "Behavior " .. n, detail = string.rep("é", 450),
          anchors = { range(unit.target.path, "new", 1) }, intent_basis = "unknown", evidence = {} }
      end
      assert(#vim.json.encode(value.units[i]) > 8192)
    end
    assert(model.validate_review(value, req))
    local maximum = answer(req)
    for _, entry in ipairs(maximum.units) do
      entry.padding = ""
      entry.padding = string.rep("x", req.output_limits.unit_bytes - #vim.json.encode(entry))
      T.eq(req.output_limits.unit_bytes, #vim.json.encode(entry))
    end
    assert(#vim.json.encode(maximum) <= req.output_limits.response_bytes, "unit allocations must fit together")
  end
end)

T.test("large configured annotation batches reserve every response array separator", function()
  local cap = 3145728
  local job = assert(review.create(fixture(300, 1), { context = { max_bytes = 1000000 },
    review = { request_max_bytes = 1000000, response_max_bytes = cap } }))
  local req = review.inspect(job).annotations[1].request
  T.eq(300, #req.units)
  local value, entries = answer(req), 0
  for _, entry in ipairs(value.units) do entries = entries + #vim.json.encode(entry) end
  -- Derive the actual envelope/commas independently from a serialized answer.
  local maximum = #vim.json.encode(value) - entries + #req.units * req.output_limits.unit_bytes
  assert(maximum <= cap, "full allocations plus all separators exceed response cap")
  assert(maximum + #req.units > cap, "assigned units should share all remaining capacity")
end)

T.test("affordable changed decision text is evidence only and annotation ownership remains local", function()
  local s = fixture(2)
  s.files[2].path = "openspec/decision.md"; s.files[2].lines[1] = "UNCHANGED RATIONALE"
  s.target.files[2].path = s.files[2].path; s.target.files[2].anchors[1].path = s.files[2].path
  s.comparison.manifest[2].path = s.files[2].path; s.comparison.manifest[2].new.path = s.files[2].path
  local job = assert(review.create(s, { review = { response_max_bytes = 8192 } }))
  local plan = review.inspect(job)
  T.eq("file2", plan.units[1].file_id)
  local req = plan.annotations[2].request
  T.eq(1, #req.units); T.eq(2, #req.files)
  assert(plan.annotations[2].prompt:find("UNCHANGED RATIONALE", 1, true))
  local value = answer(req)
  value.units[1].notes = { { summary = "Effect", detail = "Implements the requirement", intent_basis = "documented",
    anchors = { range(s.files[1].path, "new", 1) }, evidence = { range(s.files[2].path, "new", 1) } } }
  assert(model.validate_review(value, req))
  value.units[1].notes[1].anchors = { range(s.files[2].path, "new", 1) }
  T.eq(nil, model.validate_review(value, req))
end)

T.test("successful empty acknowledgements atomically assemble and replay completed records", function()
  local s, config = fixture(7), {}
  local job = assert(review.create(s, config))
  local done, calls, statuses = run(job)
  assert(done.result, done.error); T.eq(7, #done.result.files); T.eq(4, #calls)
  T.eq({ "Pending · planning", "Annotating 0%", "Annotating 42%", "Annotating 42%",
    "Annotating 85%", "Annotating 85%", "Annotating 100%", "synthesizing" }, statuses)
  local disk = vim.json.decode(vim.json.encode(done.record))
  T.eq(done.result, assert(review.validate_record(disk, s, config)))
  local encoded = vim.json.encode(disk)
  assert(not encoded:find("é中", 1, true) and not encoded:find("PATCH MUST NOT TRAVEL", 1, true))
  local replay, reused = run(assert(review.create(s, config, job)))
  assert(replay.result); T.eq(0, #reused)
  for _, mutate in ipairs({
    function(r) r.version = 9 end,
    function(r) r.snapshot_id = "wrong" end,
    function(r) table.remove(r.outputs, 1) end,
    function(r) r.outputs[#r.outputs + 1] = r.outputs[1] end,
    function(r) r.outputs[1].units[1].unit_id = "missing" end,
    function(r) r.outputs[#r.outputs].child_ids = {} end,
    function(r) r.outputs[#r.outputs].review.sections[1].evidence = { range(s.files[1].path, "new", 1) } end,
    function(r) r.source = "must not persist" end,
  }) do local corrupt = vim.deepcopy(disk); mutate(corrupt); T.eq(nil, review.validate_record(corrupt, s, config)) end
  local changed = vim.deepcopy(s); changed.files[1].lines[1] = "changed shared evidence"
  T.eq(nil, review.validate_record(disk, changed, config))
  local equivalent = vim.deepcopy(s)
  equivalent.source_buf, equivalent.source_win = 900, 901
  equivalent.comparison.manifest[1].new.supplied_from = { bufnr = 55 }
  T.eq(done.result, assert(review.validate_record(disk, equivalent, config)))
end)

T.test("failed sibling invocation is discarded and resume reuses only validated checkpoints", function()
  local s, config = fixture(7), { review = { response_max_bytes = 8192 } }
  local job = assert(review.create(s, config))
  local failed, calls = run(job, function(_, n, value)
    if n == 3 then return value, "provider failed after emitting apparently valid JSON" end
    return value
  end)
  T.eq(nil, failed.result); T.eq(nil, failed.record); T.eq(3, #calls)
  assert(failed.error:find("2/7", 1, true) and failed.error:find(":Explainr review", 1, true))
  local before = review.inspect(job).checkpoints; T.eq(2, vim.tbl_count(before))
  local done, resumed = run(assert(review.create(s, config, job)))
  assert(done.result, done.error); T.eq(6, #resumed)
  T.eq(before, review.inspect(job).checkpoints)
  local changed = vim.deepcopy(config); changed.ai = { output = function() end }
  T.eq({}, review.inspect(assert(review.create(s, changed, job))).checkpoints)
  local custom = assert(review.create(s, changed))
  run(custom, function(_, n, value) if n == 2 then return nil, "stop" end; return value end)
  assert(next(review.inspect(assert(review.create(s, changed, custom))).checkpoints))
  changed.ai.output = function() end
  T.eq({}, review.inspect(assert(review.create(s, changed, custom))).checkpoints)
  local invalid = vim.deepcopy(s); invalid.files = {}
  T.eq(nil, review.create(invalid, config, job)); T.eq(before, review.inspect(job).checkpoints)
end)

T.test("launch cap applies across phases and resets only for explicit resume", function()
  local s, config = fixture(4), { review = { max_requests = 1 } }
  local job = assert(review.create(s, config))
  local stopped, first = run(job)
  T.eq(1, #first); assert(stopped.error:find("max_requests 1", 1, true))
  local second, calls = run(job)
  T.eq(1, #calls); assert(second.error:find("synthesize", 1, true))
  local third, last = run(job)
  assert(third.result, third.error); T.eq(1, #last)
end)

T.test("freshness is checked before checkpointing and again at final atomic completion", function()
  for _, stale_at in ipairs({ 1, 2, 4 }) do
    local job, checks = assert(review.create(fixture(), {})), 0
    local done = run(job, nil, function(next)
      checks = checks + 1; next(checks ~= stale_at)
    end)
    T.eq(nil, done.result); assert(done.error:find("stale", 1, true))
    T.eq({}, review.inspect(job).checkpoints)
  end
end)

T.test("cancel retains prior checkpoints and late callbacks cannot dispatch or complete", function()
  local agent, original = require("explainr.agent"), require("explainr.agent").run
  local job = assert(review.create(fixture(4), {}))
  local callbacks, calls, completed, cancelled = {}, {}, false, 0
  agent.run = function(text, _, _, callback)
    local req = vim.json.decode(text:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)"))
    calls[#calls + 1] = req; callbacks[#callbacks + 1] = callback
    return { cancel = function() cancelled = cancelled + 1 end }
  end
  local ok, err = xpcall(function()
    local operation = review.start(job, { progress = function() end, fresh = function(done) done(true) end,
      complete = function() completed = true end })
    assert(vim.wait(1000, function() return #calls == 1 end))
    callbacks[1](vim.json.encode(answer(calls[1])))
    assert(vim.wait(1000, function() return #calls == 2 end))
    T.eq(1, vim.tbl_count(review.inspect(job).checkpoints))
    operation.cancel(); callbacks[2](vim.json.encode(answer(calls[2])))
    vim.wait(30, function() return false end)
    T.eq(1, cancelled); T.eq(2, #calls); T.eq(false, completed)
    T.eq(1, vim.tbl_count(review.inspect(job).checkpoints))
  end, debug.traceback)
  agent.run = original; assert(ok, err)
  local done, resumed = run(job); assert(done.result, done.error); T.eq(2, #resumed)
end)

T.test("cancel between annotation and synthesis prevents dispatch", function()
  local job = assert(review.create(fixture(), {}))
  local agent, original, calls, completed, operation = require("explainr.agent"), require("explainr.agent").run, 0, false, nil
  agent.run = function(text, _, _, callback)
    calls = calls + 1
    local req = vim.json.decode(text:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)"))
    vim.schedule(function() callback(vim.json.encode(answer(req))) end)
    return { cancel = function() end }
  end
  local ok, err = xpcall(function()
    operation = review.start(job, { progress = function(status) if status == "Annotating 100%" then operation.cancel() end end,
      fresh = function(done) done(true) end, complete = function() completed = true end })
    assert(vim.wait(1000, function() return vim.tbl_count(review.inspect(job).checkpoints) == 1 end))
    vim.wait(30, function() return false end); T.eq(1, calls); T.eq(false, completed)
  end, debug.traceback)
  agent.run = original; assert(ok, err)
end)

local function findings_answer(req, _, value)
  if req.phase == "annotate" then
    for i, unit in ipairs(req.units) do
      local anchor = vim.deepcopy(unit.target.anchors[1]); anchor.end_line = anchor.start_line
      value.units[i].findings = { { text = string.rep("finding ", 110), intent_basis = "documented", evidence = { anchor }, file_ids = { unit.file_id } } }
    end
  elseif req.phase == "reduce" then
    local first = req.inputs[1].findings[1]
    if first then
      local finding = vim.deepcopy(first)
      finding.text = finding.text:sub(1, math.max(1, math.floor(#finding.text / 2)))
      value.findings = { finding }
    end
  end
  return value
end

T.test("multi-level reduction rehydrates original evidence and completed replay preserves every child", function()
  local s, config = fixture(14, 3, 50), { review = { request_max_bytes = 7500, response_max_bytes = 8192 } }
  local job = assert(review.create(s, config))
  local done, calls = run(job, findings_answer)
  assert(done.result, done.error)
  local reduced, transitive, ids = 0, false, {}
  for _, call in ipairs(calls) do
    assert(call.bytes <= 7500)
    local req = call.request
    if req.phase == "reduce" then
      reduced = reduced + 1
      for _, id in ipairs(req.child_ids) do if ids[id] then transitive = true end end
      ids[req.request_id] = true
      assert(#req.files > 0)
      for _, file in ipairs(req.files) do
        T.eq(1, #file.chunks); T.eq(1, file.chunks[1].start_line)
        T.eq(s.files[1].lines[1], file.chunks[1].lines[1])
      end
    end
  end
  assert(reduced > 1 and transitive, "fixture must require multiple reduction levels")
  T.eq(done.result, assert(review.validate_record(vim.json.decode(vim.json.encode(done.record)), s, config)))
  local bad = vim.deepcopy(done.record)
  for _, output in ipairs(bad.outputs) do if output.phase == "reduce" then table.remove(output.child_ids); break end end
  T.eq(nil, review.validate_record(bad, s, config))
end)

T.test("nonreducing output fails without checkpointing and successful reductions resume", function()
  local s, config = fixture(14, 3, 50), { review = { request_max_bytes = 7500, response_max_bytes = 8192 } }
  local job = assert(review.create(s, config))
  local bad, calls = run(job, function(req, n, value)
    value = findings_answer(req, n, value)
    if req.phase == "reduce" then
      value.findings = {}; for _, child in ipairs(req.inputs) do for _, finding in ipairs(child.findings) do value.findings[#value.findings + 1] = finding end end
    end
    return value
  end)
  T.eq(nil, bad.result); assert(bad.error:find("nonprogress", 1, true), bad.error)
  T.eq("reduce", calls[#calls].request.phase)
  local reductions = 0
  local failed = run(job, function(req, n, value)
    if req.phase == "reduce" then reductions = reductions + 1; if reductions == 2 then return nil, "reducer failure" end end
    return findings_answer(req, n, value)
  end)
  assert(failed.error:find("reducer failure", 1, true))
  local checkpoints = review.inspect(job).checkpoints
  local done, resumed = run(job, findings_answer); assert(done.result, done.error)
  for _, call in ipairs(resumed) do assert(not checkpoints[call.request.request_id]); assert(call.request.phase ~= "annotate") end
end)

T.test("synthesis rejects locally present but unseen source and legacy version2 output", function()
  for _, mutate in ipairs({
    function(value) value.version = 2 end,
    function(value) value.review.sections[1].intent_basis = "documented"; value.review.sections[1].evidence = { range("src/file001.lua", "new", 1) } end,
  }) do
    local job = assert(review.create(fixture(), {}))
    local done = run(job, function(req, _, value) if req.phase == "synthesize" then mutate(value) end; return value end)
    T.eq(nil, done.result); T.eq(nil, done.record)
    T.eq(1, vim.tbl_count(review.inspect(job).checkpoints))
  end
end)

T.test("all notes assemble in unit order with exact duplicates suppressed and documented synthesis grounded", function()
  local s = fixture(2, 24, 120)
  -- A deletion has only old coordinates, independently of the added second file.
  s.files[1].side = "old"; s.target.files[1].anchors[1].side = "old"
  s.target.files[1].hunks = { { 1, 24, 0, 0 } }
  local config = { review = { request_max_bytes = 6000 } }
  local job = assert(review.create(s, config))
  local done = run(job, function(req, n, value)
    value = findings_answer(req, n, value)
    if req.phase == "annotate" then
      for i, unit in ipairs(req.units) do
        local a = vim.deepcopy(unit.target.anchors[1]); a.end_line = a.start_line
        local note = { summary = "Effect at " .. a.start_line, detail = "Behavior detail", anchors = { a }, intent_basis = "unknown", evidence = {} }
        value.units[i].notes = { note, vim.deepcopy(note) }
      end
    elseif req.phase == "synthesize" then
      local file = req.files[1]
      local section = value.review.sections[1]
      section.intent_basis, section.evidence = "documented", { range(file.path, file.side, file.chunks[1].start_line) }
    end
    return value
  end)
  assert(done.result, done.error)
  local total = 0
  for _, file in ipairs(done.result.files) do
    local previous = 0
    for _, note in ipairs(file.notes) do assert(note.anchors[1].start_line > previous); previous = note.anchors[1].start_line; total = total + 1 end
  end
  T.eq(#review.inspect(job).units, total)
  T.eq(done.result, assert(review.validate_record(done.record, s, config)))
end)

T.test("oversized annotation finding bundles split without losing findings or original evidence", function()
  local s = fixture(1, 1, 2000)
  local config = { review = { request_max_bytes = 7000, response_max_bytes = 8192 } }
  local job = assert(review.create(s, config))
  local seen = {}
  local function respond(req, _, value)
    if req.phase == "annotate" then
      for i, unit in ipairs(req.units) do
        for n = 1, 4 do value.units[i].findings[n] = { text = n .. string.rep("F", 999), intent_basis = "documented",
          evidence = unit.target.anchors, file_ids = { unit.file_id } } end
      end
    elseif req.phase == "reduce" then
      for _, child in ipairs(req.inputs) do
        for _, finding in ipairs(child.findings) do seen[#seen + 1] = finding.text:sub(1, 1) end
      end
      T.eq(s.files[1].lines, req.files[1].chunks[1].lines)
    end
    return value
  end
  local done, calls = run(job, respond)
  assert(done.result, done.error)
  T.eq({ "1", "2", "3", "4" }, seen)
  for _, call in ipairs(calls) do assert(call.bytes <= 7000) end
  T.eq(done.result, assert(review.validate_record(done.record, s, config)))
  local _, resumed = run(job); T.eq(0, #resumed)
  local interrupted, reductions = assert(review.create(s, config)), 0
  local failed = run(interrupted, function(req, n, value)
    if req.phase == "reduce" then
      reductions = reductions + 1
      if reductions == 2 then return nil, "split reducer failure" end
    end
    return respond(req, n, value)
  end)
  assert(failed.error:find("split reducer failure", 1, true), failed.error)
  local checkpoints = review.inspect(interrupted).checkpoints
  done, resumed = run(assert(review.create(s, config, interrupted)), respond)
  assert(done.result, done.error)
  for _, call in ipairs(resumed) do assert(not checkpoints[call.request.request_id]) end
end)

T.test("indivisible findings and oversized final manifest stop after annotations with size diagnostics", function()
  local s = fixture(1, 1, 2000)
  -- Annotation only needs its local manifest; reduction needs the whole manifest.
  s.comparison.manifest[2].path = string.rep("m", 2400)
  local job = assert(review.create(s, { review = { request_max_bytes = 7000, response_max_bytes = 8192 } }))
  local done, calls = run(job, function(req, _, value)
    if req.phase == "annotate" then
      value.units[1].findings = { { text = string.rep("F", 1000), intent_basis = "documented",
        evidence = req.units[1].target.anchors, file_ids = { req.units[1].file_id } } }
    end
    return value
  end)
  T.eq(nil, done.result); T.eq(1, #calls)
  assert(done.error:find("indivisible finding/evidence", 1, true) and done.error:find("7000", 1, true), done.error)
  T.eq(1, vim.tbl_count(review.inspect(job).checkpoints))
  s = fixture(); s.comparison.manifest[2].path = string.rep("m", 6000)
  done, calls = run(assert(review.create(s, { review = { request_max_bytes = 5000 } })))
  T.eq(nil, done.result); T.eq(1, #calls)
  assert(done.error:find("synthesize manifest/mandatory overhead", 1, true), done.error)
end)

T.test("reduction calls consume the same allowance and successful reductions survive a cap stop", function()
  local s, config = fixture(14, 3, 50), { review = { request_max_bytes = 7500, response_max_bytes = 8192, max_requests = 15 } }
  local job = assert(review.create(s, config))
  local done, calls = run(job, findings_answer)
  T.eq(nil, done.result); T.eq(15, #calls); T.eq("reduce", calls[15].request.phase)
  assert(done.error:find("max_requests 15", 1, true))
  repeat
    local previous = review.inspect(job).checkpoints
    local resumed
    done, resumed = run(job, findings_answer)
    assert(#resumed > 0 and #resumed <= 15)
    for _, call in ipairs(resumed) do assert(not previous[call.request.request_id]) end
    if not done.result then assert(done.error:find("max_requests 15", 1, true), done.error) end
  until done.result
end)

T.test("cancel while asynchronous freshness waits prevents late checkpoints and installation", function()
  local agent, original = require("explainr.agent"), require("explainr.agent").run
  local job = assert(review.create(fixture(), {}))
  local waiting, checks, calls, completed = nil, 0, 0, false
  agent.run = function(text, _, _, done)
    calls = calls + 1
    local req = vim.json.decode(text:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)"))
    vim.schedule(function() done(vim.json.encode(answer(req))) end)
    return { cancel = function() end }
  end
  local ok, err = xpcall(function()
    local op = review.start(job, { progress = function() end, complete = function() completed = true end,
      fresh = function(done) checks = checks + 1; if checks == 1 then done(true) else waiting = done end end })
    assert(vim.wait(1000, function() return waiting ~= nil end))
    op.cancel(); waiting(true); waiting(true)
    vim.wait(30, function() return false end)
    T.eq(1, calls); T.eq(false, completed); T.eq({}, review.inspect(job).checkpoints)
  end, debug.traceback)
  agent.run = original; assert(ok, err)
end)

T.test("completed record revalidates in a separate Neovim process without executable state", function()
  local s, config = fixture(2), { cache = { namespace = "review-process-test" } }
  local done = run(assert(review.create(s, config))); assert(done.result, done.error)
  local input = vim.json.encode({ record = done.record, snapshot = s, config = config })
  local script = string.format([[vim.opt.runtimepath:prepend(%q); local input = vim.json.decode(%q);
    local result, err = require('explainr.review').validate_record(input.record, input.snapshot, input.config);
    assert(result, err); assert(#result.files == 2); vim.cmd('qa!')]], vim.fn.getcwd(), input)
  local child = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-c", "lua " .. script }):wait(10000)
  assert(child.code == 0, child.stderr)
end)

T.test("large split review resumes mid-job, reduces multiple levels and reopens without inference", function()
  local s, config = fixture(14, 43, 100), { review = { request_max_bytes = 7500, response_max_bytes = 8192 } }
  local job = assert(review.create(s, config))
  local planned = review.inspect(job)
  assert(#planned.units > 14, "fixture must split files")
  local failed, initial = run(job, function(req, n, value)
    if n == 3 then return nil, "offline injected failure" end
    return findings_answer(req, n, value)
  end)
  T.eq(nil, failed.result); T.eq(3, #initial)
  local prior = review.inspect(job).checkpoints
  T.eq(2, vim.tbl_count(prior))
  local done, calls = run(job, findings_answer)
  assert(done.result, done.error)
  local reductions, multilevel = {}, false
  for _, call in ipairs(calls) do
    assert(not prior[call.request.request_id], "resume repeated paid work")
    assert(call.bytes <= 7500)
    if call.request.phase == "reduce" then
      for _, id in ipairs(call.request.child_ids) do if reductions[id] then multilevel = true end end
      reductions[call.request.request_id] = true
    end
  end
  assert(multilevel, "fixture must reduce more than one level")
  for _, output in ipairs(done.record.outputs) do assert(#vim.json.encode(output) <= 8192) end
  local path = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode({ snapshot = s, config = config, record = done.record }) }, path)
  local script = string.format([[vim.opt.runtimepath:prepend(%q);
    require('explainr.agent').run = function() error('reopen must not infer') end;
    local data = vim.json.decode(table.concat(vim.fn.readfile(%q), '\n'));
    local value, err = require('explainr.review').validate_record(data.record, data.snapshot, data.config);
    assert(value, err); assert(#value.files == 14); vim.cmd('qa!')]], vim.fn.getcwd(), path)
  local child = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-c", "lua " .. script }):wait(10000)
  vim.fn.delete(path)
  assert(child.code == 0, child.stderr)
  local agent, original = require("explainr.agent"), require("explainr.agent").run
  local late, dispatched, installed = nil, 0, false
  agent.run = function(text, _, _, callback)
    dispatched = dispatched + 1
    local req = vim.json.decode(text:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)"))
    late = function() callback(answer(req)) end
    return { cancel = function() end }
  end
  local ok, err = xpcall(function()
    local fresh = assert(review.create(s, config))
    local operation = review.start(fresh, { progress = function() end, fresh = function(cb) cb(true) end,
      complete = function() installed = true end })
    assert(vim.wait(3000, function() return late ~= nil end))
    operation.cancel(); late(); vim.wait(50)
    T.eq(1, dispatched); T.eq(false, installed); T.eq({}, review.inspect(fresh).checkpoints)
  end, debug.traceback)
  agent.run = original
  assert(ok, err)
end)

T.test("planner input boundary includes every UTF8 instruction and metadata byte", function()
  local s = fixture(1, 1, 200)
  local baseline = assert(review.create(s, {}))
  local size = review.inspect(baseline).annotations[1].bytes
  local exact = assert(review.create(s, { review = { request_max_bytes = size } }))
  T.eq(size, review.inspect(exact).annotations[1].bytes)
  T.eq(nil, review.create(s, { review = { request_max_bytes = size - 1 } }))
  T.eq(nil, review.create(s, { context = { max_bytes = size - 1 }, review = { request_max_bytes = size + 100 } }))
  T.eq(nil, review.create(s, { context = { max_bytes = size + 100 }, review = { request_max_bytes = size - 1 } }))
end)

T.test("bad sibling schema does not salvage any units from that invocation", function()
  local s = fixture(7)
  local job = assert(review.create(s, {}))
  local failed, calls = run(job, function(_, n, value)
    if n == 2 then value.units[2].unit_id = "wrong" end
    return value
  end)
  T.eq(nil, failed.result); T.eq(2, #calls); T.eq(1, vim.tbl_count(review.inspect(job).checkpoints))
  assert(failed.error:find("3/7", 1, true))
  local done, resumed = run(job); assert(done.result, done.error); T.eq(3, #resumed)
end)

T.test("metadata cannot own units and unit file identity cannot be reassigned", function()
  local s = fixture(2)
  local job = assert(review.create(s, {}))
  local units = review.inspect(job).units
  units[1].file_id = "file2"
  T.eq(nil, review.validate_coverage(job, units))
  s.target.files[1].file_id = "binary"
  T.eq(nil, review.create(s, {}))
end)
