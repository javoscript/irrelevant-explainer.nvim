local model = require("irrelevant_explainer.model")
local function anchor(path, side, first, last)
  return { path = path, side = side, start_line = first, end_line = last or first }
end
local snapshot = {
  mode = "diff", target = { anchors = { anchor("old.lua", "old", 2, 3), anchor("new.lua", "new", 4, 5) } },
  files = {
    { path = "old.lua", side = "old", lines = { "a", "b", "c" } },
    { path = "new.lua", side = "new", lines = { "1", "2", "3", "4", "5" } },
    { path = "spec.md", side = "new", lines = { "rule", "rationale", "unsent" }, included = { [1] = true, [2] = true } },
  },
}
local note = { summary = "Owner-only cancellation", detail = "Implements the requirement.",
  anchors = { anchor("old.lua", "old", 2), anchor("new.lua", "new", 4) },
  intent_basis = "documented", evidence = { anchor("spec.md", "new", 1, 2) } }
T.test("setup loads without agent or Diffview and validates argv", function()
  local plugin = require("irrelevant_explainer").setup()
  T.eq({ "opencode", "run", "--agent", "explain", "--format", "json" }, plugin.config.ai.command)
  T.eq("opencode", plugin.config.ai.output); T.eq(300000, plugin.config.ai.timeout_ms)
  T.eq(false, plugin.config.diff.auto_explain)
  T.eq(false, pcall(plugin.setup, { ai = { command = "echo prompt" } }))
  T.eq(false, pcall(plugin.setup, { context = { max_bytes = 0 } }))
  T.eq("auto", plugin.config.context.diff); T.eq(20, plugin.config.context.radius)
  for _, invalid in ipairs({ { diff = "partial" }, { radius = -1 }, { radius = 1.5 }, { radius = math.huge } }) do
    T.eq(false, pcall(plugin.setup, { context = invalid }))
  end
  plugin.setup({ context = { diff = "focused", radius = 0 } })
  T.eq(0, plugin.config.context.radius)
  T.eq(false, pcall(plugin.setup, { diff = { auto_explain = "true" } }))
  plugin.setup({ diff = { auto_explain = true } })
  T.eq(true, plugin.config.diff.auto_explain)
  plugin.setup()
  T.eq(nil, package.loaded["diffview"])
end)

T.test("setup replaces complete argv, keeps explicit decoders, resets and isolates caller options without spawning", function()
  local plugin = require("irrelevant_explainer")
  local system, calls = vim.system, 0
  vim.system = function() calls = calls + 1; error("setup must not spawn") end
  local ok, err = xpcall(function()
    plugin.setup(); local defaults = vim.deepcopy(plugin.config)
    for _, command in ipairs({ { "my-wrapper" }, {}, { "/path with spaces/wrapper", "two words", "$(echo unsafe);" } }) do
      local options = { ai = { command = command }, context = { radius = 3 } }
      local before = vim.deepcopy(options)
      plugin.setup(options)
      T.eq(command, plugin.config.ai.command); T.eq("opencode", plugin.config.ai.output)
      T.eq(before, options)
      command[#command + 1] = "caller-only mutation"
      T.eq(before.ai.command, plugin.config.ai.command)
      plugin.config.ai.command[1] = "config-only mutation"
      T.eq("caller-only mutation", command[#command])
      plugin.setup(); T.eq(defaults, plugin.config)
    end
    local custom = function(stdout) return stdout end
    for _, output in ipairs({ "plain", "codex", custom }) do
      local options = { ai = { command = { "my-wrapper" }, output = output } }
      plugin.setup(options); T.eq(options.ai, { command = plugin.config.ai.command, output = plugin.config.ai.output })
      T.eq(300000, plugin.config.ai.timeout_ms)
      plugin.setup(); T.eq(defaults, plugin.config)
    end
    T.eq(0, calls)
  end, debug.traceback)
  vim.system = system; plugin.setup()
  assert(ok, err)
end)

T.test("runtime automatic toggle preserves configuration and remains lazy without a pane", function()
  local plugin = require("irrelevant_explainer").setup({
    ai = { command = { "custom-agent", "--model", "custom/model" }, output = "codex", timeout_ms = 12345 },
    context = { diff = "focused", radius = 3, max_bytes = 54321 },
  })
  local config, expected = plugin.config, vim.deepcopy(plugin.config)
  local loaded = {}
  for _, name in ipairs({ "irrelevant_explainer.session", "irrelevant_explainer.ui", "diffview", "diffview.lib" }) do loaded[name] = package.loaded[name] end
  local old_notify, notices = vim.notify, {}
  vim.notify = function(message, level, options) notices[#notices + 1] = { message, level, options.title } end
  local ok, err = xpcall(function()
    T.eq(true, plugin.toggle_auto_explain()); expected.diff.auto_explain = true
    T.eq(config, plugin.config); T.eq(expected, plugin.config)
    vim.cmd("IrrelevantExplainerToggleAutoExplain"); expected.diff.auto_explain = false
    T.eq(expected, plugin.config)
    T.eq(false, plugin.config.diff.auto_explain)
    T.eq({ { "Automatic explanations enabled", vim.log.levels.INFO, "Irrelevant Explainer" },
      { "Automatic explanations disabled", vim.log.levels.INFO, "Irrelevant Explainer" } }, notices)
    plugin.setup({ diff = { auto_explain = true } })
    T.eq(false, plugin.toggle_auto_explain())
    plugin.setup({ diff = { auto_explain = true } }); T.eq(true, plugin.config.diff.auto_explain)
    plugin.setup(); T.eq(false, plugin.config.diff.auto_explain)
    for _, name in ipairs({ "irrelevant_explainer.session", "irrelevant_explainer.ui", "diffview", "diffview.lib" }) do T.eq(loaded[name], package.loaded[name]) end
  end, debug.traceback)
  vim.notify = old_notify; plugin.setup()
  assert(ok, err)
end)

T.test("paired renamed anchors and supplied evidence", function()
  local value = { version = 1, notes = { note } }
  T.eq(value, assert(model.validate(vim.json.encode(value), snapshot)))
  T.eq({ version = 1, notes = {} }, assert(model.validate('{"version":1,"notes":[]}', snapshot)))
end)
T.test("file diff priority does not forbid relevant unchanged anchors", function()
  local s = { mode = "diff", target = { scope = "file", hunks = { { 1, 1, 1, 1 } },
    anchors = { anchor("code.lua", "new", 1, 3) } }, files = {
      { path = "code.lua", side = "new", lines = { "changed call", "", "unchanged helper" } },
    } }
  local value = { version = 1, notes = { { summary = "The changed call uses the unchanged helper",
    detail = "The helper determines the changed call's behavior.", intent_basis = "inferred", evidence = {},
    anchors = { anchor("code.lua", "new", 3) } } } }
  T.eq(value, assert(model.validate(value, s)))
  s.target.anchors = { anchor("code.lua", "new", 1) }; s.target.scope = "hunk"
  local rejected, err = model.validate(value, s)
  T.eq(nil, rejected); assert(err:find("outside the focused target", 1, true))
end)

T.test("file overviews cover complete renamed, one-sided and code targets without widening other scopes", function()
  local s = vim.deepcopy(snapshot)
  s.target = { scope = "file", anchors = { anchor("old.lua", "old", 1, 3), anchor("new.lua", "new", 1, 5) } }
  local overview = { kind = "overview", summary = "File purpose and change purpose", detail = "High-level overview.",
    intent_basis = "inferred", evidence = {}, anchors = vim.deepcopy(s.target.anchors) }
  local value = { version = 1, notes = { overview } }
  T.eq(value, assert(model.validate(value, s)))
  overview.anchors = { overview.anchors[2], overview.anchors[1] } -- Side order is not significant.
  assert(model.validate(value, s))
  for _, anchors in ipairs({ { anchor("old.lua", "old", 1, 3) }, { anchor("new.lua", "new", 1, 5) } }) do
    s.target.anchors, overview.anchors = anchors, vim.deepcopy(anchors)
    assert(model.validate(value, s))
  end
  s.mode = "code"; s.files = { { path = "buffer.lua", side = "buffer", lines = { "a", "b", "c", "d" } } }
  s.target.anchors = { anchor("buffer.lua", "buffer", 1, 4) }; overview.anchors = vim.deepcopy(s.target.anchors)
  assert(model.validate(value, s))
  overview.anchors[1].end_line = 1
  local rejected, err = model.validate(value, s)
  T.eq(nil, rejected); assert(err:find("whole-file target anchors", 1, true))
  overview.anchors = vim.deepcopy(s.target.anchors)
  for _, scope in ipairs({ "selection", "hunk" }) do
    s.target.scope = scope
    T.eq(nil, model.validate(value, s))
  end
  s.target.scope = "file"; value.notes[2] = vim.deepcopy(overview)
  local duplicate, duplicate_err = model.validate(value, s)
  T.eq(nil, duplicate); assert(duplicate_err:find("only one file overview", 1, true))
  s.target.anchors = {}; s.files[1].empty = true
  T.eq(nil, model.validate({ version = 1, notes = { overview } }, s))
end)

T.test("invalid anchors, sides, evidence, summaries and JSON reject whole result", function()
  for _, mutate in ipairs({
    function(n) n.anchors[2].start_line = 3 end,
    function(n) n.anchors[2].end_line = 99 end,
    function(n) n.anchors[1].side = "buffer" end,
    function(n) n.evidence[1].end_line = 3 end,
    function(n) n.evidence[1].path = "missing.md" end,
    function(n) n.evidence = {} end,
    function(n) n.summary = "two\nrows" end,
    function(n) n.anchors[1].start_line = 2.5 end,
  }) do
    local n = vim.deepcopy(note); mutate(n)
    local value, err = model.validate({ version = 1, notes = { n } }, snapshot)
    T.eq(nil, value); assert(err:find("Invalid explanation"))
  end
  T.eq(nil, model.validate("not JSON", snapshot))
end)
T.test("buffer target contract", function()
  local s = { mode = "code", files = { { path = "[buffer:1]", side = "buffer", lines = { "a", "b" } } },
    target = { anchors = { anchor("[buffer:1]", "buffer", 2) } } }
  local n = { summary = "Returns result", detail = "Visible behavior.", intent_basis = "unknown", evidence = {},
    anchors = { anchor("[buffer:1]", "buffer", 2) } }
  assert(model.validate({ version = 1, notes = { n } }, s))
  s.files[2] = { path = "empty", side = "buffer", empty = true, lines = { "" } }
  n.intent_basis = "documented"; n.evidence = { anchor("empty", "buffer", 1) }
  T.eq(nil, model.validate({ version = 1, notes = { n } }, s))
end)

T.test("compact supplied chunks validate original coordinates and reject sparse citation gaps", function()
  local s = { mode = "diff", target = { anchors = { anchor("code.lua", "new", 9000) } }, files = {
    { path = "code.lua", side = "new", line_count = 10000,
      chunks = { { start_line = 8999, lines = { "near", "target", "near" } } } },
    { path = "spec.md", side = "new", line_count = 1000000, chunks = {
      { start_line = 100, lines = { "rule", "rationale" } }, { start_line = 103, lines = { "different rule" } },
    } },
  } }
  local n = { summary = "Visible rule", detail = "Documented supplied rule.", intent_basis = "documented",
    anchors = { anchor("code.lua", "new", 9000) }, evidence = { anchor("spec.md", "new", 100, 101) } }
  assert(model.validate({ version = 1, notes = { n } }, s))
  for _, gap in ipairs({ anchor("spec.md", "new", 100, 103), anchor("spec.md", "new", 102),
    anchor("spec.md", "new", 104), anchor("code.lua", "new", 1) }) do
    n.evidence = { gap }
    T.eq(nil, model.validate({ version = 1, notes = { n } }, s))
  end
  n.evidence = { anchor("spec.md", "new", 103) }
  assert(model.validate({ version = 1, notes = { n } }, s))
  n.anchors = { anchor("code.lua", "new", 8999) }
  T.eq(nil, model.validate({ version = 1, notes = { n } }, s))
end)

local function review_fixture()
  local s = { mode = "diff", target = { scope = "review", files = {} }, files = {}, comparison = { manifest = {} } }
  local value = { version = 2, review = { title = "Update cancellation", sections = {
    { heading = "Related changes", detail = "The policy and callers change together.", intent_basis = "documented",
      evidence = { anchor("new.lua", "new", 2) }, file_ids = { "rename", "add", "binary" } },
  } }, files = {} }
  for _, entry in ipairs({
    { "rename", { anchor("old.lua", "old", 1, 2), anchor("new.lua", "new", 1, 5) } },
    { "add", { anchor("added.lua", "new", 1, 3) } },
    { "delete", { anchor("deleted.lua", "old", 1, 4) } },
  }) do
    local target = { scope = "file", file_id = entry[1], anchors = entry[2] }
    s.target.files[#s.target.files + 1] = target
    s.comparison.manifest[#s.comparison.manifest + 1] = { file_id = entry[1] }
    for _, a in ipairs(entry[2]) do
      local lines = {}; for i = 1, a.end_line do lines[i] = "line " .. i end
      s.files[#s.files + 1] = { path = a.path, side = a.side, lines = lines }
    end
    value.files[#value.files + 1] = { file_id = entry[1], notes = {
      { kind = "overview", summary = "File purpose", detail = "Change overview.",
        anchors = vim.deepcopy(entry[2]), intent_basis = "documented", evidence = { anchor("new.lua", "new", 2) } },
    } }
  end
  s.comparison.manifest[4] = { file_id = "binary", text_unavailable = "binary" }
  s.comparison.manifest[5] = { file_id = "empty", text_unavailable = "both empty" }
  return s, value
end

T.test("review validates asymmetric independent overviews, shared evidence and explicit empty coverage", function()
  local s, value = review_fixture()
  T.eq(value, assert(model.validate(vim.json.encode(value), s)))
  value.files[2].notes = {}
  T.eq(value, assert(model.validate(value, s)))
  value.files[1], value.files[3] = value.files[3], value.files[1]
  assert(model.validate(value, s)) -- Coverage is identity-based, not position-based.
  T.eq(nil, model.validate({ version = 1, notes = {} }, s))
  s.target = s.target.files[1]
  T.eq(nil, model.validate(value, s))
end)

T.test("one invalid review sibling or section rejects atomically without changing input", function()
  local mutations = {
    function(v) table.remove(v.files) end,
    function(v) v.files[3].file_id = "add" end,
    function(v) v.files[3].file_id = "unknown" end,
    function(v) v.files[3].file_id = "binary" end,
    function(v) v.files[3].file_id = "empty" end,
    function(v) v.files[3].notes = nil end,
    function(v) v.files[3].notes = vim.empty_dict() end,
    function(v) v.files[3].notes[1].anchors = { anchor("added.lua", "new", 1, 3) } end,
    function(v) v.files[1].notes[1].anchors[2].path = "old.lua" end,
    function(v) v.files[1].notes[1].anchors[2].end_line = 4 end,
    function(v) v.files[2].notes[2] = vim.deepcopy(v.files[2].notes[1]) end,
    function(v) v.files[3].notes[1].evidence = { anchor("deleted.lua", "new", 1) } end,
    function(v) v.review = nil end,
    function(v) v.review.title = "two\nlines" end,
    function(v) v.review.title = " " end,
    function(v) v.review.sections = {} end,
    function(v) v.review.sections[1].heading = "two\rrows" end,
    function(v) v.review.sections[1].detail = "" end,
    function(v) v.review.sections[1].intent_basis = "certain" end,
    function(v) v.review.sections[1].evidence = {} end,
    function(v) v.review.sections[1].evidence[1].end_line = 6 end,
    function(v) v.review.sections[1].evidence[1].path = "missing" end,
    function(v) v.review.sections[1].file_ids = { "unknown" } end,
    function(v) v.review.sections[1].file_ids = { "add", "add" } end,
    function(v) v.review.sections[1].file_ids = vim.empty_dict() end,
  }
  for i, mutate in ipairs(mutations) do
    local s, value = review_fixture(); mutate(value)
    local before = vim.deepcopy(value)
    local accepted, err = model.validate(value, s)
    T.eq(nil, accepted); assert(err:find("file/hunk scope", 1, true), i)
    T.eq(before, value)
  end
  local s = review_fixture()
  T.eq(nil, model.validate('{"version":2,"review":', s))
end)

local function phase_fixture()
  local req = { version = 3, phase = "annotate", request_id = "request", snapshot_id = "snapshot",
    manifest = { { file_id = "code" }, { file_id = "docs" }, { file_id = "binary" } },
    files = { { path = "old.lua", side = "old", chunks = { { start_line = 5, lines = { "a", "b" } } } },
      { path = "new.lua", side = "new", chunks = { { start_line = 9, lines = { "c", "d", "e" } } } },
      { path = "adr.md", side = "new", chunks = { { start_line = 1, lines = { "rule" } }, { start_line = 3, lines = { "rationale" } } } } },
    units = { { unit_id = "unit", file_id = "code", target = { scope = "hunk",
      anchors = { anchor("old.lua", "old", 5, 6), anchor("new.lua", "new", 9, 11) } } } },
    output_limits = { response_bytes = 8192, unit_bytes = 7000, notes_per_unit = 8, findings_per_unit = 4,
      summary_bytes = 256, detail_bytes = 1024, finding_bytes = 512, evidence_per_item = 8,
      file_ids_per_item = 16, findings = 4, sections = 4, title_bytes = 256, heading_bytes = 256 } }
  local value = { version = 3, phase = req.phase, request_id = req.request_id, snapshot_id = req.snapshot_id,
    units = { { unit_id = "unit", notes = { { summary = "é中 effect", detail = "Details.",
      anchors = { anchor("old.lua", "old", 5), anchor("new.lua", "new", 9) }, intent_basis = "documented",
      evidence = { anchor("adr.md", "new", 1) } } }, findings = { { text = "A documented finding", intent_basis = "documented",
      evidence = { anchor("adr.md", "new", 3) }, file_ids = { "code", "docs" } } } } } }
  return req, value
end

T.test("version2 assembled review remains internal and cannot satisfy a version3 wire request", function()
  local snapshot, result = review_fixture()
  assert(model.validate(result, snapshot))
  local req = phase_fixture()
  T.eq(nil, model.validate_review(vim.json.encode(result), req))
end)

T.test("review identity errors disclose exact expected and received values without changing input", function()
  for _, key in ipairs({ "phase", "request_id", "snapshot_id" }) do
    for _, case in ipairs({
      { value = "echo request_id", display = '"echo request_id"' },
      { display = "<missing>" },
      { value = vim.NIL, display = "<null>" },
      { value = 42, display = "<number>" },
      { value = { secret = "DO NOT LOG OBJECTS" }, display = "<table>" },
    }) do
      local req, response = phase_fixture()
      if key ~= "phase" then
        req[key], response[key] = string.rep(key == "request_id" and "a" or "b", 64), nil
      end
      response[key] = case.value
      local before = vim.deepcopy(response)
      local accepted, err = model.validate_review(vim.json.encode(response), req)
      T.eq(nil, accepted)
      assert(err:find("wrong review " .. key .. ": expected " .. vim.json.encode(req[key])
        .. "; received " .. case.display, 1, true), err)
      assert(not err:find("DO NOT LOG OBJECTS", 1, true), err)
      T.eq(before, response)
    end
  end
end)

T.test("review identifier diagnostics escape control characters and bound multibyte values", function()
  local req, response = phase_fixture()
  response.request_id = 'bad\n"\tID'
  local accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find("received " .. vim.json.encode(response.request_id), 1, true), err)
  assert(not err:find("\n", 1, true), err)
  response.request_id = string.rep("中", 1000) .. "HIDDEN TAIL"
  accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find("received " .. vim.json.encode(string.rep("中", 128)) .. "... (3011 bytes)", 1, true), err)
  assert(#err < 2048 and not err:find("HIDDEN TAIL", 1, true), err)
end)

T.test("review reference errors identify offending file unit and child IDs", function()
  local req, response = phase_fixture()
  response.units[1].findings[1].file_ids[2] = "adr.md"
  local accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find('unknown section file_id at file_ids[2]: received "adr.md"; not in supplied manifest', 1, true), err)
  response.units[1].findings[1].file_ids[2] = { secret = "DO NOT LOG OBJECTS" }
  accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find("received <table>", 1, true) and not err:find("DO NOT LOG OBJECTS", 1, true), err)
  req, response = phase_fixture()
  response.units[1].unit_id = "wrong-unit"
  accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find('unknown unit_id: received "wrong-unit"', 1, true), err)
  req.phase, req.child_ids = "reduce", { "child-1" }
  response = { version = 3, phase = "reduce", request_id = req.request_id, snapshot_id = req.snapshot_id,
    child_ids = { "wrong-child" }, findings = {} }
  accepted, err = model.validate_review(response, req)
  T.eq(nil, accepted)
  assert(err:find('unknown child_ids: received "wrong-child"', 1, true), err)
end)

T.test("v3 annotation validates independent coordinates evidence and exact unit acknowledgements", function()
  local req, value = phase_fixture()
  T.eq(value, assert(model.validate_review(vim.json.encode(value), req)))
  value.units[1].notes, value.units[1].findings = {}, {}
  assert(model.validate_review(value, req))
  for _, mutate in ipairs({
    function(v) v.version = 2 end,
    function(v) v.phase = "synthesize" end,
    function(v) v.request_id = "other" end,
    function(v) v.snapshot_id = "other" end,
    function(v) v.units = {} end,
    function(v) v.units[2] = vim.deepcopy(v.units[1]) end,
    function(v) v.units[1].unit_id = "binary" end,
    function(v) v.units[1].unit_id = nil end,
    function(v) v.units[1].notes = nil end,
    function(v) v.units[1].findings = nil end,
    function(v) v.units[1].notes = vim.empty_dict() end,
    function(v) v.units[1].notes[1].anchors[1].start_line = 9 end,
    function(v) v.units[1].notes[1].anchors[2].end_line = 12 end,
    function(v) v.units[1].notes[1].anchors[2].path = "old.lua" end,
    function(v) v.units[1].notes[1].anchors = { anchor("adr.md", "new", 1) } end,
    function(v) v.units[1].notes[1].evidence = { anchor("adr.md", "new", 1, 3) } end,
    function(v) v.units[1].findings[1].evidence = { anchor("adr.md", "new", 2) } end,
    function(v) v.units[1].findings[1].file_ids = { "unknown" } end,
    function(v) v.units[1].findings[1].file_ids = { "code", "code" } end,
    function(v) v.units[1].findings[1].evidence = {} end,
    function(v) v.units[1].notes[1].kind = "overview" end,
    function(v) v.units[1].notes[1].summary = "multi\nline" end,
    function(v) v.raw_prompt = "forbidden" end,
  }) do
    local request, response = phase_fixture(); mutate(response)
    local before = vim.deepcopy(response)
    local accepted, err = model.validate_review(response, request)
    T.eq(nil, accepted); assert(err); T.eq(before, response)
  end
end)

T.test("v3 unsent range diagnostics identify note anchors and finding evidence without widening coverage", function()
  for _, case in ipairs({
    { path = "old.lua", side = "old", first = 5, last = 7, unsent = 7, note = true },
    { path = "adr.md", side = "new", first = 1, last = 3, unsent = 2 },
    { path = "adr.md", side = "new", first = 2, last = 2, unsent = 2 },
  }) do
    local req, value = phase_fixture()
    local bad = anchor(case.path, case.side, case.first, case.last)
    if case.note then value.units[1].notes[1].anchors[1] = bad
    else value.units[1].findings[1].evidence = { bad } end
    local accepted, err = model.validate_review(value, req)
    T.eq(nil, accepted)
    assert(err:find(string.format("%s %s:%d-%d; first unsent line %d",
      case.path, case.side, case.first, case.last, case.unsent), 1, true), err)
  end
end)

T.test("v3 finite note finding text and exact decoded UTF8 response byte allowances", function()
  local req, value = phase_fixture()
  local raw = vim.json.encode(value)
  assert(#raw > vim.fn.strchars(raw))
  req.output_limits.response_bytes = #raw
  assert(model.validate_review(raw, req))
  T.eq(nil, model.validate_review(raw .. " ", req))
  req.output_limits.response_bytes = #raw - 1
  T.eq(nil, model.validate_review(raw, req))
  for _, mutate in ipairs({
    function(r) r.output_limits.notes_per_unit = 0 end,
    function(r) r.output_limits.findings_per_unit = 0 end,
    function(r) r.output_limits.summary_bytes = 2 end,
    function(r) r.output_limits.detail_bytes = 2 end,
    function(r) r.output_limits.finding_bytes = 2 end,
    function(r) r.output_limits.evidence_per_item = 0 end,
    function(r) r.output_limits.file_ids_per_item = 1 end,
    function(r) r.output_limits.unit_bytes = 20 end,
  }) do local r, v = phase_fixture(); mutate(r); T.eq(nil, model.validate_review(v, r)) end
end)

T.test("v3 whole-file overview remains optional exact and restricted to its own unit", function()
  local req, value = phase_fixture()
  req.units[1].target.scope = "file"
  value.units[1].notes[1].kind = "overview"
  value.units[1].notes[1].anchors = vim.deepcopy(req.units[1].target.anchors)
  assert(model.validate_review(value, req))
  value.units[1].notes[2] = vim.deepcopy(value.units[1].notes[1])
  T.eq(nil, model.validate_review(value, req))
  value.units[1].notes[2] = nil; value.units[1].notes[1].anchors[2].end_line = 10
  T.eq(nil, model.validate_review(value, req))
end)

T.test("v3 reduction and synthesis require all children and only current original evidence", function()
  local req, annotation = phase_fixture()
  req.units, req.phase, req.child_ids = nil, "reduce", { "a", "b" }
  local reduced = { version = 3, phase = "reduce", request_id = req.request_id, snapshot_id = req.snapshot_id,
    child_ids = { "b", "a" }, findings = annotation.units[1].findings }
  assert(model.validate_review(reduced, req))
  for _, ids in ipairs({ { "a" }, { "a", "a" }, { "a", "b", "c" } }) do
    local value = vim.deepcopy(reduced); value.child_ids = ids; T.eq(nil, model.validate_review(value, req))
  end
  local stale = vim.deepcopy(reduced); stale.findings[1].evidence = { anchor("adr.md", "new", 1, 3) }
  T.eq(nil, model.validate_review(stale, req))
  req.phase = "synthesize"
  local value = { version = 3, phase = "synthesize", request_id = req.request_id, snapshot_id = req.snapshot_id,
    child_ids = { "a", "b" }, review = { title = "Change", sections = { { heading = "Relationship", detail = "Text",
      intent_basis = "documented", evidence = { anchor("adr.md", "new", 3) }, file_ids = { "code", "binary" } } } } }
  assert(model.validate_review(value, req))
  for _, mutate in ipairs({
    function(v) v.review.sections = {} end,
    function(v) v.review.title = "" end,
    function(v) v.review.title = "two\nlines" end,
    function(v) v.review.sections[1].heading = "two\nlines" end,
    function(v) v.review.sections[1].detail = "" end,
    function(v) v.review.sections[1].anchors = {} end,
    function(v) v.review.sections[1].file_ids = { "unseen" } end,
    function(v) v.review.sections[1].evidence = {} end,
    function(v) v.review.sections[1].evidence = { anchor("adr.md", "new", 2) } end,
    function(v) v.units = {} end,
  }) do local v = vim.deepcopy(value); mutate(v); T.eq(nil, model.validate_review(v, req)) end
  -- A citation in input findings is not authorization without its source text.
  req.files = {}; T.eq(nil, model.validate_review(value, req))
end)
