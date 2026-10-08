local identity = require("explainr.identity")
local code, api = require("explainr.code"), vim.api

local function key(snapshot, config) return select(2, identity.key(snapshot, config)) end
local function fixture()
  return { mode = "diff", cwd = "/identity/worktree", worktree_root = "/identity/worktree",
    target = { scope = "review", files = { { file_id = "a", anchors = {
      { path = "a", side = "new", start_line = 1, end_line = 2 } } } } },
    files = { { path = "a", side = "new", lines = { "α", "context" }, endofline = true,
      present = true, mode = "100644", supplied_from = "filesystem" } },
    comparison = { identities = { old = { type = "commit", commit = "abc", track_head = true },
      new = { type = "local" } }, selection = { kind = "working", path_args = {}, show_untracked = false },
      manifest = { { path = "a", old = { present = false }, new = { present = true } } } },
    context = { strategy = "review", radius = 20, omitted_files = 0 } }
end
local function config()
  return { ai = { command = { "agent", "--secret=value" }, output = "plain", timeout_ms = 100 },
    context = { max_bytes = 262144, diff = "auto", radius = 20 },
    review = { request_max_bytes = 65536, response_max_bytes = 32768, max_requests = 128,
      max_snapshot_bytes = 16777216 }, cache = { namespace = "default", max_bytes = 104857600, enabled = true } }
end

T.test("identity canonical serialization is ordered typed and SHA256", function()
  T.eq(identity.canonical({ z = 1, a = { 2, 3 } }), identity.canonical({ a = { 2, 3 }, z = 1 }))
  assert(identity.hash({ [1] = "a" }) ~= identity.hash({ ["1"] = "a" }))
  assert(identity.hash({ "ab", "c" }) ~= identity.hash({ "a", "bc" }))
  T.eq(vim.fn.sha256(identity.canonical({ a = "α" })), identity.hash({ a = "α" }))
  T.eq(64, #identity.hash({}))
end)

T.test("identity target preserves asymmetric byte and virtual offsets without mutation", function()
  local target = { scope = "selection", text = "α\n   ", selection = { pos1 = { 17, 4, 2, 0 } },
    spans = { { { 17, 4, 2, 0 }, { 17, 4, 3, 0 } }, { { 17, 5, 1, 2 }, { 17, 5, 1, 5 } } } }
  local normalized = identity.target(target)
  T.eq(nil, normalized.selection)
  T.eq({ { { 0, 4, 2, 0 }, { 0, 4, 3, 0 } }, { { 0, 5, 1, 2 }, { 0, 5, 1, 5 } } }, normalized.spans)
  T.eq(target.text, normalized.text)
  T.eq(17, target.spans[1][1][1])
  assert(target.selection)
end)

local function buffer(run)
  local previous, buf = api.nvim_get_current_buf(), api.nvim_create_buf(false, false)
  local ve = vim.o.virtualedit
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "aé中z", "\talpha", "0123456789", "unselected context" })
  vim.bo[buf].tabstop = 8
  vim.o.virtualedit = "block"
  local ok, err = xpcall(function() run(buf) end, debug.traceback)
  vim.o.virtualedit = ve
  api.nvim_set_current_buf(previous)
  api.nvim_buf_delete(buf, { force = true })
  assert(ok, err)
end
local function selection(kind, first, last)
  local s, err = code.collect(0, "selection", { type = kind, pos1 = first, pos2 = last, exclusive = false })
  assert(s, err)
  return s
end

T.test("identity recreated unnamed multibyte selections reverse equivalently with strict freshness", function()
  local first
  buffer(function(buf)
    first = selection("v", { buf, 1, 2, 0 }, { buf, 1, 4, 0 })
    T.eq("é中", first.target.text)
    T.eq("[unnamed]", first.files[1].path)
    T.eq(true, code.fresh(first))
  end)
  buffer(function(buf)
    local second = selection("v", { buf, 1, 4, 0 }, { buf, 1, 2, 0 })
    assert(first.source_buf ~= second.source_buf)
    T.eq(first.fingerprint, second.fingerprint)
    T.eq(key(first), key(second))
    T.eq(false, code.fresh(first))
    T.eq(true, code.fresh(second))
    assert(second.target.selection)
    local other = selection("v", { buf, 1, 4, 0 }, { buf, 1, 7, 0 })
    assert(key(other) ~= key(second))
    api.nvim_buf_set_lines(buf, 3, 4, false, { "changed context only" })
    local changed = selection("v", { buf, 1, 2, 0 }, { buf, 1, 4, 0 })
    T.eq(second.target.text, changed.target.text)
    assert(key(changed) ~= key(second))
  end)
end)

T.test("identity block tabs retain exact virtual coverage across direction and buffer IDs", function()
  local first
  buffer(function(buf)
    first = selection(string.char(22), { buf, 2, 1, 2 }, { buf, 3, 6, 0 })
    T.eq("    \n2345", first.target.text)
    T.eq({ { { 0, 2, 1, 2 }, { 0, 2, 1, 6 } }, { { 0, 3, 3, 0 }, { 0, 3, 6, 0 } } },
      identity.target(first.target).spans)
  end)
  buffer(function(buf)
    local reversed = selection(string.char(22), { buf, 3, 6, 0 }, { buf, 2, 1, 2 })
    T.eq(key(first), key(reversed))
    T.eq(first.fingerprint, reversed.fingerprint)
    local other = vim.deepcopy(reversed)
    other.target.spans[1][1][4] = 3
    assert(key(other) ~= key(reversed))
  end)
end)

T.test("identity equal selection text at different byte columns misses and exclusive boundaries normalize", function()
  buffer(function(buf)
    api.nvim_buf_set_lines(buf, 0, 1, false, { "aaaa" })
    local first = selection("v", { buf, 1, 1, 0 }, { buf, 1, 2, 0 })
    local second = selection("v", { buf, 1, 2, 0 }, { buf, 1, 3, 0 })
    T.eq(first.target.text, second.target.text)
    assert(key(first) ~= key(second))
    local exclusive = assert(code.collect(0, "selection", { type = "v", exclusive = true,
      pos1 = { buf, 1, 1, 0 }, pos2 = { buf, 1, 3, 0 } }))
    T.eq(first.fingerprint, exclusive.fingerprint)
    T.eq(key(first), key(exclusive))
  end)
end)

T.test("identity unnamed code files reuse after recreation without runtime ownership reuse", function()
  local first
  buffer(function() first = assert(code.collect(0, "file")) end)
  buffer(function()
    local second = assert(code.collect(0, "file"))
    T.eq(key(first), key(second))
    T.eq(first.fingerprint, second.fingerprint)
    T.eq(false, code.fresh(first))
    T.eq(true, code.fresh(second))
  end)
end)

T.test("identity all five routed targets remain distinct even for a shared buffer", function()
  local keys = {}
  for _, pair in ipairs({ { "code", "selection" }, { "code", "file" }, { "diff", "file" },
    { "diff", "hunk" }, { "diff", "review" } }) do
    local s = fixture()
    s.mode, s.target.scope, s.source_buf = pair[1], pair[2], 42
    local value = key(s)
    assert(not keys[value]); keys[value] = true
  end
end)

T.test("identity exact comparison context metadata and coverage changes miss", function()
  local original = fixture()
  for _, mutate in ipairs({
    function(s) s.files[1].lines[2] = "new context" end,
    function(s) s.files[1].endofline = false end,
    function(s) s.files[1].present = false end,
    function(s) s.files[1].mode = "100755" end,
    function(s) s.comparison.identities.old.commit = "def" end,
    function(s) s.comparison.identities.new.type = "stage" end,
    function(s) s.comparison.selection.kind = "staged" end,
    function(s) s.comparison.selection.path_args = { "a" } end,
    function(s) s.comparison.selection.show_untracked = true end,
    function(s) s.context.radius = 1 end,
    function(s) s.files[1].chunks = { { start_line = 8, lines = { "elsewhere" } } } end,
    function(s) s.comparison.manifest[1].old.present = true end,
  }) do
    local copy = vim.deepcopy(original); mutate(copy)
    assert(key(copy) ~= key(original))
  end
end)

T.test("identity worktrees nonGit cwd and named sources are isolated", function()
  local original, copy = fixture(), fixture()
  copy.worktree_root = "/identity/linked-worktree"
  assert(key(original) ~= key(copy))
  original.worktree_root, copy.worktree_root = nil, nil
  copy.cwd = "/identity/unrelated"
  assert(key(original) ~= key(copy))
  original.mode, copy.mode, copy.cwd = "code", "code", original.cwd
  copy.files[1].path = "another"
  assert(key(original) ~= key(copy))
end)

T.test("identity generation and explicit version changes miss", function()
  local s, cfg = fixture(), config()
  for _, mutate in ipairs({
    function(c) c.ai.command[2] = "--other" end,
    function(c) c.ai.output = "codex" end,
    function(c) c.cache.namespace = "another" end,
    function(c) c.cache.decoder_key = "v2" end,
    function(c) c.context.max_bytes = 100000 end,
    function(c) c.context.radius = 7 end,
    function(c) c.context.diff = "focused" end,
    function(c) c.review.request_max_bytes = 30000 end,
    function(c) c.review.response_max_bytes = 16000 end,
  }) do
    local copy = vim.deepcopy(cfg); mutate(copy)
    assert(key(s, copy) ~= key(s, cfg))
  end
  for _, name in ipairs({ "FORMAT_VERSION", "PROMPT_VERSION", "PLANNER_VERSION" }) do
    local before, version = key(s, cfg), identity[name]
    identity[name] = version + 1
    local after = key(s, cfg)
    identity[name] = version
    assert(before ~= after)
  end
end)

T.test("identity operational and ephemeral display changes do not invalidate", function()
  local s, cfg = fixture(), config()
  s.comparison.manifest[1].comparison = vim.deepcopy(s.comparison.identities)
  local copy, c = vim.deepcopy(s), vim.deepcopy(cfg)
  copy.source_buf, copy.changedtick, copy.windows = 200, 999, { old = 100, new = 101 }
  copy.selected_file, copy.source, copy.timestamp, copy.fingerprint = "other", 100, 9999, "runtime"
  copy.entrypoint, copy.opening_method = "Lua", "automatic"
  copy.files[1].supplied_from = "loaded-buffer"
  copy.comparison.identities.old.track_head = false
  copy.comparison.manifest[1].comparison.old.track_head = false
  c.ai.timeout_ms, c.cache.enabled, c.cache.max_bytes = 1, false, 1
  c.review.max_requests, c.review.max_snapshot_bytes = 1, 1
  T.eq(key(s, cfg), key(copy, c))
end)

T.test("identity custom decoders require stable keys not function addresses", function()
  local s, cfg = fixture(), config()
  cfg.ai.output = function() end
  local source, request = identity.key(s, cfg)
  T.eq(nil, source); T.eq(nil, request)
  cfg.cache.decoder_key = "decoder-v1"
  local before = key(s, cfg)
  cfg.ai.output = function() return "different closure" end
  T.eq(before, key(s, cfg)) -- Runtime reuse must separately check function identity.
  cfg.cache.decoder_key = "decoder-v2"
  assert(before ~= key(s, cfg))
end)
