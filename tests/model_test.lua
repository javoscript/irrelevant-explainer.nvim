local model = require("explainr.model")
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
  local plugin = require("explainr").setup()
  T.eq({}, plugin.config.ai.command)
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

T.test("runtime automatic toggle preserves configuration and remains lazy without a pane", function()
  local plugin = require("explainr").setup({
    ai = { command = { "custom-agent", "--model", "custom/model" }, output = "codex", timeout_ms = 12345 },
    context = { diff = "focused", radius = 3, max_bytes = 54321 },
  })
  local config, expected = plugin.config, vim.deepcopy(plugin.config)
  local loaded = {}
  for _, name in ipairs({ "explainr.session", "explainr.ui", "diffview", "diffview.lib" }) do loaded[name] = package.loaded[name] end
  local old_notify, notices = vim.notify, {}
  vim.notify = function(message, level, options) notices[#notices + 1] = { message, level, options.title } end
  local ok, err = xpcall(function()
    T.eq(true, plugin.toggle_auto_explain()); expected.diff.auto_explain = true
    T.eq(config, plugin.config); T.eq(expected, plugin.config)
    vim.cmd("ExplainrToggleAutoExplain"); expected.diff.auto_explain = false
    T.eq(expected, plugin.config)
    T.eq(false, plugin.config.diff.auto_explain)
    T.eq({ { "Automatic explanations enabled", vim.log.levels.INFO, "Explainr" },
      { "Automatic explanations disabled", vim.log.levels.INFO, "Explainr" } }, notices)
    plugin.setup({ diff = { auto_explain = true } })
    T.eq(false, plugin.toggle_auto_explain())
    plugin.setup({ diff = { auto_explain = true } }); T.eq(true, plugin.config.diff.auto_explain)
    plugin.setup(); T.eq(false, plugin.config.diff.auto_explain)
    for _, name in ipairs({ "explainr.session", "explainr.ui", "diffview", "diffview.lib" }) do T.eq(loaded[name], package.loaded[name]) end
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
  for _, scope in ipairs({ "function", "class", "selection", "hunk" }) do
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
