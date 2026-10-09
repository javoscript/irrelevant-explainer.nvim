local M = { FORMAT_VERSION = 1, PROMPT_VERSION = 2, PLANNER_VERSION = 2 }

-- Typed keys avoid collisions between array coordinates and object fields.
-- This is an identity encoding, not a wire JSON representation.
function M.canonical(value, pause)
  if type(value) ~= "table" then return vim.json.encode(value) end
  if pause then pause() end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) < type(b) end
    return a < b
  end)
  for index, key in ipairs(keys) do
    if pause and index % 32 == 0 then pause() end
    parts[#parts + 1] = M.canonical(key, pause) .. ":" .. M.canonical(value[key], pause)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.hash(value, pause) return vim.fn.sha256(M.canonical(value, pause)) end

function M.target(target)
  local copy = vim.deepcopy(target)
  copy.selection = nil -- Retained only for runtime refresh, never supplied evidence.
  for _, span in ipairs(copy.spans or {}) do
    for _, pos in ipairs(span) do
      -- Keep getregionpos's {buffer, line, byte, virtual-offset} shape, but use
      -- its conventional zero buffer placeholder rather than a runtime handle.
      pos[1] = 0
    end
  end
  return copy
end

local function strip_origins(value)
  if type(value) == "table" then
    value.supplied_from = nil
    -- Revisions occur both at comparison.identities and in manifest entries.
    -- track_head describes opening/refresh behavior, not the resolved commit.
    if value.type == "commit" then value.track_head = nil end
    for _, child in pairs(value) do
      if type(child) == "table" then strip_origins(child) end
    end
  end
end

local function supplied(value)
  local copy = vim.deepcopy(value)
  strip_origins(copy)
  return copy
end

local function namespace(snapshot)
  local cwd = snapshot.cwd or vim.fn.getcwd()
  local path = snapshot.mode == "code" and snapshot.files[1].path or nil
  local start = path and path ~= "[unnamed]" and vim.fs.dirname(path) or cwd
  local root = snapshot.worktree_root or vim.fs.root(start, ".git")
  if root then return { worktree = vim.uv.fs_realpath(root) or root } end
  return { cwd = vim.uv.fs_realpath(cwd) or cwd, path = path }
end

-- Return only digests. In particular, raw argv (possibly containing secrets)
-- and source content must never be copied into a persistent cache envelope.
function M.key(snapshot, config, pause)
  config = config or {}
  local ai, cache = config.ai or {}, config.cache or {}
  local decoder = ai.output or "plain"
  if type(decoder) == "function" then
    if type(cache.decoder_key) ~= "string" or cache.decoder_key == "" then return nil, nil end
    decoder = { custom = cache.decoder_key }
  else decoder = { builtin = decoder, key = cache.decoder_key } end
  local source = namespace(snapshot)
  local source_hash = M.hash(source)
  local comparison = supplied(snapshot.comparison)
  local generation = vim.deepcopy(ai)
  generation.command, generation.output, generation.timeout_ms = nil, nil, nil
  local review = vim.deepcopy(config.review or {})
  review.max_requests, review.max_snapshot_bytes = nil, nil
  local key = M.hash({
    format = M.FORMAT_VERSION, prompt = M.PROMPT_VERSION, planner = M.PLANNER_VERSION,
    response = snapshot.target.scope == "review" and 3 or 1,
    source = source_hash, mode = snapshot.mode, scope = snapshot.target.scope,
    target = M.hash(M.target(snapshot.target), pause),
    context = M.hash({ files = supplied(snapshot.files), comparison = comparison, context = snapshot.context }, pause),
    generation = M.hash({ command = M.hash(ai.command or {}), decoder = decoder,
      ai = generation, context = config.context or {}, review = review, namespace = cache.namespace or "default" }),
  })
  return source_hash, key
end

return M
