local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("explainr.ui")
local geometry_ns = api.nvim_create_namespace("explainr.geometry")
local range_ns = api.nvim_create_namespace("explainr.ranges")
local loading_ns = api.nvim_create_namespace("explainr.loading")
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local intent = {
  documented = { "D", "ExplainrDocumented" },
  inferred = { "~", "ExplainrInferred" },
  unknown = { "?", "ExplainrUnknown" },
}

local function highlights()
  for name, link in pairs({ ExplainrSummary = "Normal", ExplainrDocumented = "DiagnosticOk",
    ExplainrInferred = "DiagnosticWarn", ExplainrUnknown = "DiagnosticInfo", ExplainrMetadata = "Comment",
    ExplainrHeading = "Title", ExplainrTitle = "DiagnosticInfo" }) do
    api.nvim_set_hl(0, name, { default = true, link = link })
  end
  -- Mark expanded anchors in the gutter, never on the code/diff text.
  local metadata = api.nvim_get_hl(0, { name = "Comment", link = false })
  api.nvim_set_hl(0, "ExplainrActiveRange", { default = true, fg = metadata.fg, ctermfg = metadata.ctermfg })
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  local accent = api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false })
  local dark = vim.o.background == "dark"
  local background, foreground = normal.bg or (dark and 0x181818 or 0xffffff), accent.fg or 0x639dc9
  -- Soften the theme's neutral surface rather than inventing a grayscale tint
  -- or borrowing a diagnostic color. Background-less themes use their text.
  local surface = api.nvim_get_hl(0, { name = "CursorLine", link = false })
  if not surface.bg then surface = api.nvim_get_hl(0, { name = "NormalFloat", link = false }) end
  local color = surface.bg or normal.fg or (dark and 0xdddddd or 0x222222)
  local active = 0
  local muted, backdrop, source_muted = 0, 0, 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local base = math.floor(background / 2 ^ shift) % 256
    local tint = math.floor(color / 2 ^ shift) % 256
    active = active + math.floor(base + (tint - base) * (surface.bg and 0.5 or 0.08)) * 2 ^ shift
    local text = math.floor((normal.fg or (dark and 0xdddddd or 0x222222)) / 2 ^ shift) % 256
    local shade = math.floor(base * (dark and 0.65 or 0.96))
    backdrop = backdrop + shade * 2 ^ shift
    muted = muted + math.floor(shade + (text - shade) * 0.2) * 2 ^ shift
    source_muted = source_muted + math.floor(base + (text - base) * 0.4) * 2 ^ shift
  end
  api.nvim_set_hl(0, "ExplainrDetailContext", { default = true, fg = muted, bg = backdrop,
    ctermfg = dark and 239 or 250, ctermbg = dark and 233 or 254 })
  api.nvim_set_hl(0, "ExplainrDetailBackdrop", { default = true, fg = normal.fg, bg = backdrop,
    ctermfg = normal.ctermfg, ctermbg = dark and 233 or 254 })
  api.nvim_set_hl(0, "ExplainrDetailGutter", { default = true, fg = metadata.fg, bg = backdrop,
    ctermfg = metadata.ctermfg, ctermbg = dark and 233 or 254 })
  api.nvim_set_hl(0, "ExplainrDetailActive", { default = true, bg = active,
    ctermbg = surface.ctermbg or (dark and 235 or 255) })
  -- Foreground only: outside the anchors, retain native diff backgrounds/signs.
  api.nvim_set_hl(0, "ExplainrSourceContext", { default = true, fg = source_muted, ctermfg = dark and 242 or 246 })
  local tint = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local base, accent = math.floor(background / 2 ^ shift) % 256, math.floor(foreground / 2 ^ shift) % 256
    tint = tint + math.floor(base + (accent - base) * 0.04) * 2 ^ shift
  end
  api.nvim_set_hl(0, "ExplainrLoading", { default = true, bg = tint, ctermbg = dark and 234 or 255 })
  for level = 1, 8 do
    local color = 0
    for _, shift in ipairs({ 16, 8, 0 }) do
      local base, tint = math.floor(background / 2 ^ shift) % 256, math.floor(foreground / 2 ^ shift) % 256
      color = color + math.floor(base + (tint - base) * (0.25 + level / 8 * 0.75)) * 2 ^ shift
    end
    api.nvim_set_hl(0, "ExplainrLoadingRail" .. level, { default = true, fg = color,
      ctermfg = dark and (236 + level * 2) or (253 - level * 2) })
  end
  -- [+] is a UI control, not a Markdown shortcut link. Don't inherit link
  -- underlines/error decorations from the lower-priority Markdown highlighter.
  local special = api.nvim_get_hl(0, { name = "Special", link = false })
  api.nvim_set_hl(0, "ExplainrDetailCue", { default = true, fg = special.fg, ctermfg = special.ctermfg, nocombine = true })
end

local function mark(buf, row, first, last, hl)
  if last > first then
    api.nvim_buf_set_extmark(buf, ns, row, first, { end_col = last, hl_group = hl,
      priority = hl == "ExplainrSummary" and 90 or 110 })
  end
end

local function single_line(text)
  return vim.trim(text:gsub("%s+", " "))
end

-- The background and accepted text stay steady; only a one-cell gutter glows.
-- A 2.4-second eased cycle cascades through every requested range.
local function loading_rail(chunks, width, frame, coordinate)
  local phase = ((frame - 1 - coordinate * 2) % 24) / 24
  local level = 1 + math.floor(7 * (1 - math.cos(phase * 2 * math.pi)) / 2 + 0.5)
  local result, column = { { "▊", { "ExplainrLoadingRail" .. level, "ExplainrLoading" } } }, 1
  if width > 1 then result[#result + 1] = { " ", { "Normal", "ExplainrLoading" } }; column = 2 end
  local function append(char, hl)
    if column >= width then return end
    local cells = vim.fn.strdisplaywidth(char)
    local groups = type(hl) == "table" and vim.list_extend(vim.deepcopy(hl), { "ExplainrLoading" })
      or { hl or "Normal", "ExplainrLoading" }
    local last = result[#result]
    if last and vim.deep_equal(last[2], groups) then last[1] = last[1] .. char
    else result[#result + 1] = { char, groups } end
    column = column + cells
  end
  for _, chunk in ipairs(chunks) do
    for index = 0, vim.fn.strchars(chunk[1], true) - 1 do
      local char = vim.fn.strcharpart(chunk[1], index, 1, true)
      if column + vim.fn.strdisplaywidth(char) > width then
        while column < width do append(" ") end
        return result
      end
      append(char, chunk[2])
      if column >= width then return result end
    end
  end
  while column < width do append(" ") end
  return result
end

local function start_markdown(buf)
  -- Parser installation is optional; native semantic marks remain the fallback.
  pcall(vim.treesitter.start, buf, "markdown")
end

local function skipped_rows(win, view)
  if view.skipcol == 0 then return 0 end
  -- start_vcol excludes preceding filler; end_vcol is exclusive.
  return api.nvim_win_text_height(win, { start_row = view.topline - 1, end_row = view.topline - 1,
    start_vcol = 0, end_vcol = view.skipcol }).all
end

-- Distance between native viewport origins, including virtual and diff filler.
-- Start at the first line's text and end just before the last line's text:
-- filler belongs to the latter boundary, not to the former.
local function display_distance(win, before, after)
  local distance = before.topfill - after.topfill
  if before.topline ~= after.topline then
    local first, last = math.min(before.topline, after.topline), math.max(before.topline, after.topline)
    local rows = api.nvim_win_text_height(win, { start_row = first - 1, end_row = last - 1,
      start_vcol = 0, end_vcol = 0 }).all
    distance = distance + (after.topline > before.topline and rows or -rows)
  end
  return distance + skipped_rows(win, after) - skipped_rows(win, before)
end

-- One entry per *display* row, not per buffer line. Explicitly excluding filler
-- from text height lets us retain deletions and virtual lines as separate rows.
-- Expanded context needs the remaining source, not just the current viewport.
function M.project(win, through_eof, from_start)
  local info = vim.fn.getwininfo(win)[1]
  if not info then return {} end
  return api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    if from_start then
      view = { topline = 1, skipcol = 0,
        topfill = api.nvim_win_text_height(win, { start_row = 0, end_row = 0 }).fill }
    end
    local rows, line = {}, view.topline
    local count = api.nvim_buf_line_count(info.bufnr)
    local limit = through_eof and math.huge or info.height
    while #rows < limit and line <= count do
      local fold = vim.fn.foldclosedend(line)
      local last = fold >= 0 and fold or line
      local fill = line == view.topline and view.topfill
        or api.nvim_win_text_height(win, { start_row = line - 1, end_row = line - 1 }).fill
      for index = 1, math.min(fill, limit - #rows) do
        rows[#rows + 1] = { line = line, last = last, filler = true, offset = index - fill - 1 }
      end
      local height = api.nvim_win_text_height(win, {
        start_row = line - 1, end_row = line - 1,
        start_vcol = line == view.topline and view.skipcol or 0,
      }).all
      for _ = 1, math.min(math.max(1, height), limit - #rows) do
        rows[#rows + 1] = { line = line, last = last, folded = fold >= 0 }
      end
      line = last + 1
    end
    if vim.wo[win].diff and line > count and #rows < limit then
      for offset = 1, math.min(math.max(0, vim.fn.diff_filler(count + 1)), limit - #rows) do
        rows[#rows + 1] = { line = count, last = count, filler = true, eof = true, offset = offset }
      end
    end
    while #rows < info.height do rows[#rows + 1] = { empty = true } end
    return rows
  end)
end

local function shorten(value, width, suffix)
  if vim.fn.strdisplaywidth(value) <= width then return value end
  suffix = suffix or " … [+]"
  local chars = vim.fn.strchars(value)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(value, 0, chars) .. suffix) > width do
    chars = chars - 1
  end
  return vim.fn.strcharpart(value, 0, chars) .. (width >= vim.fn.strdisplaywidth(suffix) and suffix or "+")
end

-- Measure literal text, not winbar formatting; clip once across all segments.
local function header(chunks, width)
  local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, chunks))
  -- strdisplaywidth also accounts for the current reader's 'linebreak'.
  -- A winbar never wraps, even when its Markdown buffer does.
  local clipped = text
  if vim.fn.strwidth(text) > width then
    local chars = vim.fn.strchars(text)
    while chars > 0 and vim.fn.strwidth(vim.fn.strcharpart(text, 0, chars) .. "…") > width do chars = chars - 1 end
    clipped = vim.fn.strcharpart(text, 0, chars) .. "…"
  end
  local remaining = #clipped - (clipped ~= text and #"…" or 0)
  local bar = {}
  for _, chunk in ipairs(chunks) do
    local value = chunk[1]:sub(1, remaining)
    if value ~= "" then
      bar[#bar + 1] = "%#" .. (chunk[2] or "ExplainrMetadata") .. "#" .. value:gsub("%%", "%%%%")
      remaining = remaining - #value
    end
  end
  if clipped ~= text then bar[#bar + 1] = "%#ExplainrMetadata#…" end
  return table.concat(bar) .. "%#ExplainrMetadata#"
end

-- Native comparison coordinates omit wraps/folds but include diff filler.
-- They remain shared when the source windows have unequal widths/heights or
-- are stacked vertically. Then project that coordinate into the followed
-- viewport, rather than copying the other window's physical screen row.
local function comparison_lines(win)
  return api.nvim_win_call(win, function()
    local result, row = {}, 0
    for line = 1, api.nvim_buf_line_count(0) do
      row = row + math.max(0, vim.fn.diff_filler(line)) + 1
      result[line] = row
    end
    result[#result + 1] = row + math.max(0, vim.fn.diff_filler(api.nvim_buf_line_count(0) + 1)) + 1
    return result
  end)
end

function M.open(source, snapshot, result, on_close, keymaps)
  local current = api.nvim_get_current_win()
  api.nvim_set_current_win(source)
  vim.cmd("botright vsplit")
  local win, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  highlights()
  vim.treesitter.language.register("markdown", "explainr")
  -- The aligned overview stays alive while its window displays Markdown.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "explainr"
  vim.b[buf].explainr_loading_folds = {}
  vim.b[buf].explainr_foldtext = {}
  api.nvim_win_set_buf(win, buf)
  start_markdown(buf)
  local options = { diff = false, scrollbind = false, cursorbind = false, wrap = false,
    conceallevel = 0,
    number = false, relativenumber = false, signcolumn = "yes:1", statuscolumn = "  ", foldcolumn = "0", foldenable = true,
    foldmethod = "manual", foldminlines = 0, foldlevel = 0,
    foldtext = "get(b:explainr_loading_folds, string(v:foldstart), get(b:explainr_foldtext, string(v:foldstart), getline(v:foldstart)))",
    list = false, scrolloff = 0, sidescrolloff = 0, spell = false, colorcolumn = "", fillchars = "eob: " }
  for name, value in pairs(options) do vim.wo[win][name] = value end
  api.nvim_set_current_win(current)
  local pane = { win = win, buf = buf, source = source, snapshot = snapshot, result = result,
    status = "Ready", rows = {}, closed = false, frame = 1, folds = {} }
  pane.group = api.nvim_create_augroup("ExplainrPane" .. win, { clear = true })
  local detail_ns = api.nvim_create_namespace("explainr.detail." .. win)
  local focus_ns = api.nvim_create_namespace("explainr.focus." .. win)
  local overview_focus_ns = api.nvim_create_namespace("explainr.overview.focus." .. win)
  local detail_sources = {}
  local wheel_down = api.nvim_replace_termcodes("<ScrollWheelDown>", true, false, true)
  local wheel_up = api.nvim_replace_termcodes("<ScrollWheelUp>", true, false, true)
  vim.on_key(function(_, typed)
    if typed ~= "" then
      pane.wheel_input = typed == wheel_down or typed == wheel_up
      if pane.detail_win and pane:windows()[api.nvim_get_current_win()] then
        if typed == "z" then pane.fold_prefix = true
        elseif pane.fold_prefix and not typed:match("^%d$") then
          if ("cCoOaAMRrmxXEfFdDv"):find(typed, 1, true) then pane.detail_folds_dirty = true end
          pane.fold_prefix = nil
        end
      end
    end
  end, detail_ns)
  local function clear_detail_marks()
    for source_buf in pairs(detail_sources) do
      if api.nvim_buf_is_valid(source_buf) then
        api.nvim_buf_clear_namespace(source_buf, detail_ns, 0, -1)
        api.nvim_buf_clear_namespace(source_buf, focus_ns, 0, -1)
      end
    end
    detail_sources = {}
  end

  function pane:note_ids()
    local row = api.nvim_win_get_cursor(self.win)[1]
    local first = api.nvim_win_call(self.win, function() return vim.fn.foldclosed(row) end)
    if first >= 0 then row = first end
    local ids = vim.deepcopy(self.rows[row] or {})
    local last = api.nvim_win_call(self.win, function() return vim.fn.foldclosedend(row) end)
    if last >= row then
      for _, line in ipairs(self.populated or {}) do
        if line > row and line <= last then vim.list_extend(ids, self.rows[line]) end
      end
    end
    return ids
  end

  function pane:counter(ids)
    local order, selected = self.note_order or {}, {}
    for _, id in ipairs(ids) do selected[id] = true end
    local first, last
    for position, id in ipairs(order) do
      if selected[id] then first, last = first or position, position end
    end
    if first then return first .. (last > first and "–" .. last or "") .. " / " .. #order end
    return #order .. (#order == 1 and " explanation" or " explanations")
  end

  function pane:source_focus(ids)
    clear_detail_marks()
    if #ids == 0 then return end
    -- Include the paired diff buffer even for a one-sided addition/deletion.
    -- Never decorate a replacement buffer after the review changes files.
    for side, source_win in pairs(self.snapshot and self.snapshot.windows or {}) do
      if api.nvim_win_is_valid(source_win) then
        local source_buf = api.nvim_win_get_buf(source_win)
        local captured = self.snapshot.capture and self.snapshot.capture.state.panes[side]
        local expected = captured and captured.buf or self.snapshot.source_buf
        if not expected or expected == source_buf then detail_sources[source_buf] = {} end
      end
    end
    for _, id in ipairs(ids) do
      for _, a in ipairs(self.result.notes[id].anchors) do
        local source_win = self.snapshot and self.snapshot.windows[a.side]
        if source_win and api.nvim_win_is_valid(source_win) then
          local source_buf = api.nvim_win_get_buf(source_win)
          if detail_sources[source_buf] and a.end_line <= api.nvim_buf_line_count(source_buf) then
            table.insert(detail_sources[source_buf], { a.start_line - 1, a.end_line })
            for row = a.start_line - 1, a.end_line - 1 do
              api.nvim_buf_set_extmark(source_buf, detail_ns, row, 0, {
                sign_text = "▎", sign_hl_group = "ExplainrActiveRange", priority = 5,
              })
            end
          end
        end
      end
    end
    for source_buf, ranges in pairs(detail_sources) do
      table.sort(ranges, function(a, b) return a[1] < b[1] end)
      local first, count = 0, api.nvim_buf_line_count(source_buf)
      -- Dim the complement of the union, including off-screen/wrapped text.
      ranges[#ranges + 1] = { count, count }
      for _, range in ipairs(ranges) do
        if first < range[1] then
          api.nvim_buf_set_extmark(source_buf, focus_ns, first, 0, {
            end_row = range[1], end_col = 0, hl_group = "ExplainrSourceContext", priority = 200,
          })
        end
        first = math.max(first, range[2])
      end
    end
  end

  function pane:focus(clear)
    if self.closed or self.detail_win or not api.nvim_win_is_valid(self.win) then return end
    local ids = not clear and self.result and not self.status:match("^Stale")
      and api.nvim_get_current_win() == self.win and self:note_ids() or {}
    if not vim.deep_equal(self.focus_ids, ids) then self:source_focus(ids); self.focus_ids = ids end
    api.nvim_buf_clear_namespace(self.buf, overview_focus_ns, 0, -1)
    if #ids == 0 and not self.focus_highlight then return end
    if #ids > 0 and not self.focus_highlight then
      self.focus_highlight = vim.wo[self.win].winhighlight
      local mappings = {}
      for from, to in self.focus_highlight:gmatch("([^,:]+):([^,]+)") do mappings[from] = to end
      for _, name in ipairs({ "Normal", "NormalNC", "EndOfBuffer" }) do mappings[name] = "ExplainrDetailBackdrop" end
      local values = {}
      for from, to in pairs(mappings) do values[#values + 1] = from .. ":" .. to end
      vim.wo[self.win].winhighlight = table.concat(values, ",")
    elseif #ids == 0 and self.focus_highlight then
      vim.wo[self.win].winhighlight, self.focus_highlight = self.focus_highlight, nil
    end
    local ranges = {}
    for _, id in ipairs(ids) do vim.list_extend(ranges, self:ranges(self.result.notes[id].anchors, self.snapshot.windows)) end
    local function active(coordinate, last)
      for _, range in ipairs(ranges) do
        if coordinate <= range[2] and (last or coordinate) >= range[1] then return true end
      end
      return false
    end
    local width = api.nvim_win_get_width(self.win) - vim.fn.getwininfo(self.win)[1].textoff
    local function chunks(values, selected)
      local styled, size = {}, 0
      for _, chunk in ipairs(values) do
        local text = selected and chunk[1] == "│ " and "▎ " or chunk[1]
        styled[#styled + 1] = { text, selected and { chunk[2], "ExplainrDetailActive" } or "ExplainrDetailContext" }
        size = size + vim.fn.strdisplaywidth(text)
      end
      styled[#styled + 1] = { string.rep(" ", math.max(0, width - size)),
        selected and "ExplainrDetailActive" or "ExplainrDetailContext" }
      return styled
    end
    local seen = {}
    for _, item in ipairs(self.projection or {}) do
      if #ids > 0 and not item.empty and not item.filler and not item.eof and not seen[item.line] then
        local coordinates = self:coordinates(self.source)
        local coordinate, ref = self.overflow[item.line] or coordinates[item.line], self.references[item.line]
        if not ref then
          for _, range in ipairs(self.note_ranges) do
            if coordinate > range[1] and coordinate <= range[2] then ref = "│ "; break end
          end
        end
        local values = { { ref or "", "ExplainrMetadata" } }
        if not self.logical_overlays[item.line] then
          if item.folded then values = { { self.fold_labels[tostring(item.line)] or "", "ExplainrSummary" } }
          else
            for _, span in ipairs(self.line_spans[item.line]) do
              local last = math.min(span[2], #self.lines[item.line])
              if last > span[1] then values[#values + 1] = { self.lines[item.line]:sub(span[1] + 1, last), span[3] } end
            end
          end
        else values = {} end
        local selected = active(coordinate, item.folded and coordinates[item.last] or nil)
        api.nvim_buf_set_extmark(self.buf, overview_focus_ns, item.line - 1, 0, {
          virt_text = chunks(values, selected), virt_text_pos = "overlay", virt_text_win_col = 0, priority = 160,
        })
        seen[item.line] = true
      end
    end
    for _, geometry in ipairs(self.virtual_geometry or {}) do
      geometry.unfocused = geometry.unfocused or vim.deepcopy(geometry.opts)
      geometry.opts = vim.deepcopy(geometry.unfocused)
      if #ids > 0 then
        for index, coordinate in ipairs(geometry.coordinates) do
          geometry.opts.virt_lines[index] = chunks(geometry.opts.virt_lines[index], active(coordinate))
        end
      end
      api.nvim_buf_set_extmark(self.buf, geometry_ns, geometry.row, 0, geometry.opts)
    end
    self:loading()
  end

  local function focused()
    local context = pane.snapshot and pane.snapshot.context
    if not context or context.strategy ~= "focused" then return end
    local omitted = context.omitted_files or {}
    local count = type(omitted) == "number" and omitted or #omitted
    return string.format("Focused ±%s · %d files omitted", tostring(context.radius or "?"), count)
  end

  function pane:windows()
    local windows = { [self.source] = true }
    local owners = { self.snapshot or {}, self.pending or {} }
    vim.list_extend(owners, self.queued or {})
    for _, owner in ipairs(owners) do
      for _, candidate in pairs(owner.windows or {}) do
        if api.nvim_win_is_valid(candidate) then windows[candidate] = true end
      end
    end
    return windows
  end

  function pane:detail_valid()
    local layout = self.detail_layout
    if not layout then return true end
    if not api.nvim_win_is_valid(self.win) or api.nvim_win_get_buf(self.win) ~= self.detail_buf then return false end
    for candidate, captured in pairs(layout.buffers) do
      if not api.nvim_win_is_valid(candidate) or api.nvim_win_get_buf(candidate) ~= captured then return false end
    end
    return true
  end

  function pane:headers(clear)
    local windows = not clear and self:windows() or {}
    self.source_headers = self.source_headers or {}
    self.updating_state = true
    for source_win, original in pairs(self.source_headers) do
      if not windows[source_win] then
        if api.nvim_win_is_valid(source_win) and vim.wo[source_win].winbar == " " then vim.wo[source_win].winbar = original end
        self.source_headers[source_win] = nil
      end
    end
    -- Reserve this row from opening, never when a particular result arrives.
    for source_win in pairs(windows) do
      if api.nvim_win_is_valid(source_win) and vim.wo[source_win].winbar == "" then
        self.source_headers[source_win] = ""
        vim.wo[source_win].winbar = " "
      end
    end
    self.updating_state = false
  end

  function pane:coordinates(candidate)
    self.comparison = self.comparison or {}
    local source_buf = api.nvim_win_get_buf(candidate)
    local tick = api.nvim_buf_get_changedtick(source_buf)
    local cached = self.comparison[candidate]
    if not cached or cached.buf ~= source_buf or cached.tick ~= tick then
      cached = { buf = source_buf, tick = tick, lines = comparison_lines(candidate) }
      self.comparison[candidate] = cached
    end
    return cached.lines
  end

  function pane:locate(coordinate, candidate)
    local target = self:coordinates(candidate or self.source)
    local count = #target - 1
    local low, high = 1, count + 1
    while low < high do
      local mid = math.floor((low + high) / 2)
      if target[mid] < coordinate then low = mid + 1 else high = mid end
    end
    return low > count and { row = count, eof = true, offset = coordinate - target[count] }
      or { row = low, offset = coordinate < target[low] and coordinate - target[low] or nil }
  end

  function pane:sync_sources(line, from, scrolling)
    from = from or self.source
    local coordinate = self:coordinates(from)[line]
    if scrolling and vim.wo[from].scrollbind then
      -- cursorbind can leave a counterpart inside its own scrolloff margin.
      -- Validate it before syncbind computes distances: its native scrolldown
      -- otherwise validates AFTER calculating them and scrolls twice.
      for candidate in pairs(self:windows()) do
        if candidate ~= from and vim.wo[candidate].scrollbind then
          api.nvim_win_call(candidate, vim.fn.winline)
        end
      end
    end
    api.nvim_win_call(from, function()
      if vim.wo.scrollbind then vim.cmd("syncbind") end
    end)
    -- syncbind leaves bound cursors inside their own native scrolloff margins.
    -- Forcing an identical code row after a viewport scroll can violate a
    -- counterpart's larger margin and trigger a second bound scroll on redraw.
    if scrolling then return end
    for candidate in pairs(self:windows()) do
      if candidate ~= from and vim.wo[candidate].diff and vim.wo[from].diff then
        local target = self:locate(coordinate, candidate).row
        local other = api.nvim_win_get_cursor(candidate)
        local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(candidate), target - 1, target, false)[1] or ""
        api.nvim_win_set_cursor(candidate, { target, math.min(other[2], math.max(0, #text - 1)) })
      end
    end
  end

  local function reference(note)
    local refs = {}
    for _, anchor in ipairs(note.anchors) do
      refs[#refs + 1] = anchor.side .. ":" .. anchor.start_line
        .. (anchor.end_line ~= anchor.start_line and "–" .. anchor.end_line or "")
    end
    return "[" .. table.concat(refs, " ↔ ") .. "] "
  end

  -- All whole-buffer comparison work happens on structural updates, never
  -- on animation ticks. Intervals can then be intersected with the viewport.
  function pane:ranges(anchors, windows)
    local ranges = {}
    for _, anchor in ipairs(anchors or {}) do
      local candidate = (windows or {})[anchor.side]
      if candidate and api.nvim_win_is_valid(candidate) then
        local coordinates = self:coordinates(candidate)
        local first, last = coordinates[anchor.start_line], coordinates[anchor.end_line]
        if first and last then ranges[#ranges + 1] = { first, last } end
      end
    end
    return ranges
  end

  function pane:prepare_pending()
    self.pending_ranges = {}
    local requests = self.pending and { self.pending } or {}
    vim.list_extend(requests, self.queued or {})
    for _, request in ipairs(requests) do
      local target = request.snapshot and request.snapshot.target
      if target then
        self.pending_ranges[request] = self:ranges(target.anchors, request.windows)
      elseif request.scope == "file" then
        self.pending_ranges[request] = { { 1, math.huge } }
      else
        -- Before collection a hunk is explicitly provisional: cursor plus the
        -- adjacent native changed region. This bounded scan runs once per phase.
        local candidate = request.source
        if candidate and api.nvim_win_is_valid(candidate) then
          local count = api.nvim_buf_line_count(api.nvim_win_get_buf(candidate))
          local first = math.min(count, request.row or 1)
          local last = first
          api.nvim_win_call(candidate, function()
            local function changed(line) return vim.fn.diff_hlID(line, 1) ~= 0 end
            if vim.wo.diff and changed(first) then
              local limit = api.nvim_win_get_height(candidate)
              while first > 1 and last - first < limit and changed(first - 1) do first = first - 1 end
              while last < count and last - first < limit and changed(last + 1) do last = last + 1 end
            end
          end)
          local coordinates = self:coordinates(candidate)
          self.pending_ranges[request] = { {
            coordinates[first - 1] and coordinates[first - 1] + 1 or 1, coordinates[last] } }
        end
      end
    end
  end

  function pane:loading()
    if self.closed or self.detail_win or not self.lines then return end
    api.nvim_buf_clear_namespace(self.buf, loading_ns, 0, -1)
    local width = api.nvim_win_get_width(self.win) - vim.fn.getwininfo(self.win)[1].textoff
    -- Repainting the glyph/background under a block cursor looks like cursor
    -- flicker. Leave its logical row native; other requested rails still glow.
    local cursor_line = api.nvim_get_current_win() == self.win and api.nvim_win_get_cursor(self.win)[1]
    local coordinates = self.comparison and self.comparison[self.source]
    if not coordinates then return end
    local ranges = {}
    if self.pending and self.status:match("^Pending") then
      local requests = { self.pending }
      vim.list_extend(requests, self.queued or {})
      for _, request in ipairs(requests) do
        local target = request.snapshot and request.snapshot.target
        if target then
          -- Snapshot delivery can refine anchors between ticks. Only use
          -- cached coordinates here: no native geometry or whole-file scans.
          for _, anchor in ipairs(target.anchors or {}) do
            local candidate = (request.windows or {})[anchor.side]
            local cached = self.comparison[candidate]
            if cached then
              local first, last = cached.lines[anchor.start_line], cached.lines[anchor.end_line]
              if first and last then ranges[#ranges + 1] = { first, last } end
            end
          end
        else vim.list_extend(ranges, (self.pending_ranges or {})[request] or {}) end
      end
    end
    local function matches(first, last)
      for _, range in ipairs(ranges) do
        if first <= range[2] and (last or first) >= range[1] then return true end
      end
      return false
    end
    -- Reuse just the visible virtual rows (including deletion/EOF filler).
    -- Updating extmarks cannot emit TextChanged or require native geometry.
    for _, geometry in ipairs(self.virtual_geometry or {}) do
      local opts = vim.deepcopy(geometry.opts)
      for index, coordinate in ipairs(geometry.coordinates) do
        if matches(coordinate) then
          opts.virt_lines[index] = loading_rail(opts.virt_lines[index], width, self.frame, coordinate)
        end
      end
      api.nvim_buf_set_extmark(self.buf, geometry_ns, geometry.row, 0, opts)
    end
    local seen, loading_folds = {}, {}
    for _, item in ipairs(self.projection or {}) do
      if not item.empty then
        local coordinate = (self.overflow[item.line] or coordinates.lines[item.line]) + (item.offset or 0)
        local last = coordinates.lines[item.last] or coordinate
        if matches(coordinate, item.folded and last or coordinate) then
          if item.folded and item.line ~= cursor_line then
            loading_folds[tostring(item.line)] = "▊ "
              .. ((self.fold_labels or {})[tostring(item.line)] or "[folded]")
          end
          if not item.filler and not item.eof and item.line ~= cursor_line and not seen[item.line] then
            local text = item.folded and ((self.fold_labels or {})[tostring(item.line)] or "[folded]") or self.lines[item.line]
            local ref = not item.folded and (self.references[item.line] or "") or ""
            if not item.folded and ref == "" then
              for _, range in ipairs(self.note_ranges or {}) do
                if coordinate > range[1] and coordinate <= range[2] then ref = "│ "; break end
              end
            end
            -- Wrapped continuation rows have their summary in virtual context
            -- above; don't duplicate it on the navigable cursor segment.
            if self.logical_overlays[item.line] then text, ref = "", "" end
            local chunks = { { ref, "ExplainrMetadata" } }
            if not item.folded and text ~= "" then
              for _, span in ipairs(self.line_spans[item.line]) do
                local last = math.min(span[2], #text)
                if last > span[1] then chunks[#chunks + 1] = { text:sub(span[1] + 1, last), span[3] } end
              end
            else chunks[#chunks + 1] = { text, "ExplainrSummary" } end
            api.nvim_buf_set_extmark(self.buf, loading_ns, item.line - 1, 0, {
              virt_text = loading_rail(chunks, width, self.frame, coordinate),
              virt_text_pos = "overlay", virt_text_win_col = 0, priority = 180,
            })
            seen[item.line] = true
          end
        end
      end
    end
    vim.b[self.buf].explainr_loading_folds = loading_folds
  end

  function pane:header(ids)
    if self.closed or not api.nvim_win_is_valid(self.win) or not api.nvim_win_is_valid(self.source) then return end
    local width = api.nvim_win_get_width(self.win)
    local counter = self:counter(ids or (self.detail_win and self.detail_layout.ids or self:note_ids()))
      .. (self.auto_explain and " · Auto" or "")
    local title = width >= 60 and "Explainr · " or ""
    if vim.fn.strwidth(title .. counter) > width then title = "" end
    -- Do not spend the last cell on an ellipsis when the count/mode just fit.
    local compact = vim.fn.strwidth(counter) + 1 >= width
    if self.detail_win or compact then
      local bar = header({ { title ~= "" and "Explainr" or "", "ExplainrTitle" },
        { (title ~= "" and " · " or "") .. counter .. (compact and "" or " · Expanded · Enter/K back · n/p notes") } }, width)
      self.updating_state = true
      if vim.wo[self.win].winbar ~= bar then vim.wo[self.win].winbar = bar end
      if not self.detail_win then vim.b[self.buf].explainr_status = self.status end
      self.updating_state = false
      return
    end
    local pending = self.status:match("^Pending")
    local label = (pending and api.nvim_get_current_win() ~= self.win
      and spinner[(self.frame - 1) % #spinner + 1] .. " " or "") .. self.status
    local queued = pending and self.queued and #self.queued > 0 and " · " .. #self.queued .. " queued" or ""
    local context = focused()
    if context then label = label .. " · " .. context end
    local legend = width >= 50 and "D documented · ~ inferred · ? unknown" or "D doc · ~ inferred · ? unknown"
    counter = counter .. " · "
    if vim.fn.strwidth(counter .. label .. queued .. title .. " · " .. legend) > width then
      legend = "D doc · ~ inferred · ? unknown"
      if vim.fn.strwidth(counter .. label .. queued .. title .. " · " .. legend) > width then
        legend = "D · ~ inferred · ?"
      end
    end
    local budget = width - vim.fn.strwidth(legend .. queued .. title .. counter) - 3
    if vim.fn.strwidth(label) > budget then
      local chars = vim.fn.strchars(label)
      while chars > 0 and vim.fn.strwidth(vim.fn.strcharpart(label, 0, chars)) > budget - 1 do chars = chars - 1 end
      label = vim.fn.strcharpart(label, 0, chars) .. "…"
    end
    local chunks = { { title ~= "" and "Explainr" or "", "ExplainrTitle" },
      { (title ~= "" and " · " or "") .. counter .. label .. queued .. " · " } }
    local first = 1
    for index = 1, #legend do
      local symbol = legend:sub(index, index)
      for _, cue in pairs(intent) do
        if symbol == cue[1] then
          chunks[#chunks + 1] = { legend:sub(first, index - 1) }
          chunks[#chunks + 1] = { symbol, cue[2] }
          first = index + 1
          break
        end
      end
    end
    chunks[#chunks + 1] = { legend:sub(first) }
    local bar = header(chunks, width)
    self.updating_state = true
    if vim.wo[self.win].winbar ~= bar then vim.wo[self.win].winbar = bar end
    -- Statusline (including laststatus=3/lualine) belongs entirely to the user.
    vim.b[self.buf].explainr_status = self.status
    self.updating_state = false
  end

  function pane:state()
    if self.closed or self.detail_win or not api.nvim_win_is_valid(self.win) or not api.nvim_win_is_valid(self.source) then return end
    self:header()
    self:loading()
  end

  function pane:stop_spinner()
    if self.timer then self.timer:stop(); self.timer:close(); self.timer = nil end
  end

  function pane:animate()
    self:stop_spinner()
    if self.closed or not self.status:match("^Pending") then return end
    local timer = vim.uv.new_timer()
    self.timer = timer
    timer:start(100, 100, vim.schedule_wrap(function()
      -- A scheduled tick may outlive stop/close or a subsequent pending phase.
      if self.closed or self.timer ~= timer then return end
      self.frame = self.frame + 1
      self:state()
    end))
  end

  -- Only the visible geometry needs native text-height/fold queries. Notes
  -- outside the viewport are still ordinary, addressable logical buffer lines.
  function pane:fold_label(first, last)
    local ids, summaries = {}, {}
    for _, line in ipairs(self.populated or {}) do
      if line >= first and line <= last then vim.list_extend(ids, self.rows[line]) end
    end
    local share = math.floor((api.nvim_win_get_width(self.win) - 15 - 3 * math.max(0, #ids - 1)) / math.max(1, #ids))
    for _, id in ipairs(ids) do
      local note = self.result.notes[id]
      local prefix = reference(note) .. (intent[note.intent_basis] or intent.unknown)[1] .. " "
      summaries[#summaries + 1] = prefix .. shorten(single_line(note.summary),
        math.max(6, share - vim.fn.strdisplaywidth(prefix)))
    end
    return #summaries > 0 and shorten("▎ [folded] " .. table.concat(summaries, " · ") .. " [+]",
      api.nvim_win_get_width(self.win)) or ""
  end

  function pane:project(through_eof, from_start)
    local rows, extra_row = M.project(self.source, through_eof, from_start), self.source_count + 1
    for index, item in ipairs(rows) do
      if item.empty and extra_row <= #self.lines then
        rows[index] = { line = extra_row, last = extra_row }
        extra_row = extra_row + 1
      end
    end
    if through_eof then
      for row = extra_row, #self.lines do rows[#rows + 1] = { line = row, last = row } end
    end
    return rows
  end

  function pane:align()
    if self.closed or self.detail_win or not api.nvim_win_is_valid(self.source) or not api.nvim_win_is_valid(self.win) then return end
    self:headers()
    if self.source_count ~= api.nvim_buf_line_count(api.nvim_win_get_buf(self.source)) then self:render(); return end
    self.projection = self:project()
    local view = api.nvim_win_call(self.source, vim.fn.winsaveview)
    local source_cursor = api.nvim_win_get_cursor(self.source)
    local notes_cursor = api.nvim_win_get_cursor(self.win)[1]
    local overflow = api.nvim_get_current_win() == self.win and self.overflow[notes_cursor]
    local keep_overflow = overflow and self:locate(overflow).row == source_cursor[1]
    -- Overflow annotations occupy otherwise unused rows, including real rows
    -- below EOF. Keep source geometry intact; their references/cursors still
    -- target the original anchor, not the annotation's presentation row.
    local info = vim.fn.getwininfo(self.source)[1]
    local cursor_row = vim.fn.screenpos(self.source, source_cursor[1], source_cursor[2] + 1).row
      - info.winrow - info.winbar + 1
    local visible, folded, labels, text_rows, first_text = {}, {}, {}, {}, {}
    for index, item in ipairs(self.projection) do
      if not item.empty and not item.eof and item.line <= self.source_count then
        visible[item.line] = item
        if not item.filler then
          text_rows[item.line] = (text_rows[item.line] or 0) + 1
          first_text[item.line] = first_text[item.line] or index
        end
        if item.folded then folded[item.line] = item.last end
      end
    end
    if vim.wo[self.source].diff then
      local coordinates = self:coordinates(self.source)
      for line in pairs(visible) do
        -- Match comparison_lines' diff-only coordinates. text_height.fill also
        -- counts plugin virtual lines, which rebuilding can never reconcile.
        local fill = api.nvim_win_call(self.source, function() return math.max(0, vim.fn.diff_filler(line)) end)
        if coordinates[line] - (coordinates[line - 1] or 0) - 1 ~= fill then
          -- Native linematch can refine an off-screen hunk when it becomes
          -- visible, without changing text or emitting DiffUpdated. Validate
          -- only the viewport; rebuild cached coordinates only on a mismatch.
          self.comparison = nil
          if not self.rendering then self:render() end
          return false
        end
      end
    end
    -- Retain closed off-screen folds, but opening a fold can scroll its start
    -- out of view. Validate cached ranges, not just visible fold-start lines.
    local changed = false
    for first, last in pairs(self.folds) do
      local closed = last <= #self.lines and api.nvim_win_call(self.source, function()
        return vim.fn.foldclosed(first) == first and vim.fn.foldclosedend(first) == last
      end)
      if not closed then self.folds[first] = nil; changed = true end
    end
    for first, last in pairs(folded) do
      local owned = api.nvim_win_call(self.win, function() return vim.fn.foldclosedend(first) end)
      if self.folds[first] ~= last or owned ~= last then self.folds[first] = last; changed = true end
    end
    for first, last in pairs(self.folds) do
      labels[tostring(first)] = self:fold_label(first, last)
    end
    self.fold_labels = labels
    vim.b[self.buf].explainr_foldtext = labels
    if changed then
      api.nvim_win_call(self.win, function()
        vim.cmd("silent! normal! zE")
        for first, last in pairs(self.folds) do vim.cmd(string.format("%d,%dfold", first, last)) end
      end)
    end
    api.nvim_buf_clear_namespace(self.buf, geometry_ns, 0, -1)
    api.nvim_buf_clear_namespace(self.buf, range_ns, 0, -1)
    self.virtual_geometry = {}
    self.logical_overlays = {}
    local function virtual_mark(line, rows, above, coordinates)
      local opts = { virt_lines = rows, virt_lines_above = above }
      opts.id = api.nvim_buf_set_extmark(self.buf, geometry_ns, line - 1, 0, opts)
      self.virtual_geometry[#self.virtual_geometry + 1] = { row = line - 1, opts = opts, coordinates = coordinates }
    end
    local function rail(coordinate)
      for _, range in ipairs(self.note_ranges) do
        if coordinate > range[1] and coordinate <= range[2] then return "│ " end
      end
      return ""
    end
    local width = api.nvim_win_get_width(self.win) - vim.fn.getwininfo(self.win)[1].textoff
    local notes_topfill = view.topfill
    for line in pairs(visible) do
      -- Clip a very long wrapped line to its visible portion. Its logical
      -- cursor must stay visible even when the source line fills the screen.
      local height = math.max(1, text_rows[line] or 0)
      local skipped = line == view.topline and view.skipcol > 0
      local before = line == source_cursor[1] and first_text[line]
        and math.max(0, math.min(height - 1, cursor_row - first_text[line])) or 0
      local fill = api.nvim_win_text_height(self.source, { start_row = line - 1, end_row = line - 1 }).fill
      local virtual, below, virtual_coords, below_coords = {}, {}, {}, {}
      local coordinate = self:coordinates(self.source)[line]
      local start_fill = line == view.topline and view.topfill > info.height and view.topfill or math.min(fill, info.height)
      local end_fill = math.max(1, start_fill - info.height + 1)
      for offset = -start_fill, -end_fill do
        local text = self.filler[line] and self.filler[line][offset] or ""
        local ref = self.filler_refs[line] and self.filler_refs[line][offset] or rail(coordinate + offset)
        virtual[#virtual + 1] = { { ref, "ExplainrMetadata" }, { shorten(text, math.max(1, width - vim.fn.strdisplaywidth(ref))), "ExplainrSummary" } }
        virtual_coords[#virtual_coords + 1] = coordinate + offset
      end
      local ref = self.references[line]
      if ref then
        api.nvim_buf_set_extmark(self.buf, range_ns, line - 1, 0, {
          virt_text = { { ref, "ExplainrMetadata" } }, virt_text_pos = "inline", priority = 120,
        })
      elseif rail(coordinate) ~= "" then
        api.nvim_buf_set_extmark(self.buf, range_ns, line - 1, 0, {
          virt_text = { { "│ ", "ExplainrMetadata" } }, virt_text_pos = "inline", priority = 120,
        })
      end
      -- Keep the navigable logical row on the source cursor's wrap segment,
      -- with the summary on the first segment and blank continuations around it.
      for index = 1, before do
        virtual[#virtual + 1] = { { index == 1 and not skipped
          and (self.references[line] or "") .. self.lines[line] or "", "ExplainrSummary" } }
        virtual_coords[#virtual_coords + 1] = coordinate
      end
      for _ = before + 2, height do
        below[#below + 1] = { { "", "Normal" } }
        below_coords[#below_coords + 1] = coordinate
      end
      if before > 0 or skipped then
        self.logical_overlays[line] = true
        local hl = line == source_cursor[1] and vim.wo[self.win].cursorline and "CursorLine" or "Normal"
        api.nvim_buf_set_extmark(self.buf, geometry_ns, line - 1, 0, {
          virt_text = { { string.rep(" ", width), hl } }, virt_text_pos = "overlay", priority = 150,
        })
      end
      if #virtual > 0 then
        virtual_mark(line, virtual, true, virtual_coords)
      end
      if line == self.source_count then
        for offset = 1, math.min(self.eof_fill, info.height) do
          local ref = self.eof_refs[offset] or rail(coordinate + offset)
          below[#below + 1] = { { ref, "ExplainrMetadata" }, { shorten(self.eof[offset] or "", math.max(1, width - vim.fn.strdisplaywidth(ref))), "ExplainrSummary" } }
          below_coords[#below_coords + 1] = coordinate + offset
        end
      end
      if #below > 0 then virtual_mark(line, below, false, below_coords) end
      if line == view.topline then
        notes_topfill = math.min(view.topfill, info.height) + before
      end
    end
    for line in pairs(self.overflow) do
      if line > self.source_count then
        api.nvim_buf_set_extmark(self.buf, range_ns, line - 1, 0, {
          virt_text = { { self.references[line], "ExplainrMetadata" } }, virt_text_pos = "inline", priority = 120,
        })
      end
    end
    api.nvim_win_call(self.win, function()
      vim.fn.winrestview({ topline = view.topline, topfill = notes_topfill, leftcol = 0,
        lnum = keep_overflow and notes_cursor or source_cursor[1], col = 0 })
    end)
    self:state()
    self:focus()
    self.scroll_views = {}
    for candidate in pairs(self:windows()) do self.scroll_views[candidate] = api.nvim_win_call(candidate, vim.fn.winsaveview) end
    self.scroll_views[self.win] = api.nvim_win_call(self.win, vim.fn.winsaveview)
  end

  function pane:render()
    if self.closed or self.rendering or not api.nvim_win_is_valid(self.source) or not api.nvim_win_is_valid(self.win) then return end
    if not self:detail_valid() then return end
    self.rendering = true
    self.detail_context_cache = nil
    self:headers()
    self.focus_ids = nil
    self.rows, self.locations = {}, {}
    self.overflow = {}
    local lines, spans = {}, {}
    local count = api.nvim_buf_line_count(api.nvim_win_get_buf(self.source))
    self.source_count = count
    for row = 1, count do lines[row] = ""; self.rows[row] = {}; spans[row] = {} end
    self.filler = {}
    self.eof = {}
    self.filler_refs, self.eof_refs, self.references, self.note_ranges = {}, {}, {}, {}
    self.eof_fill = api.nvim_win_call(self.source, function() return math.max(0, vim.fn.diff_filler(count + 1)) end)
    local width = api.nvim_win_get_width(self.win) - vim.fn.getwininfo(self.win)[1].textoff
    -- Coordinate scans are cached by buffer revision, not repeated on cursor
    -- events, resize, focus changes, or animation ticks.
    for candidate in pairs(self:windows()) do self:coordinates(candidate) end
    self:prepare_pending()
    local entries = {}
    if self.result then
      for index, note in ipairs(self.result.notes) do
        local ranges = self:ranges(note.anchors, self.snapshot and self.snapshot.windows)
        vim.list_extend(self.note_ranges, ranges)
        local projected, foreign
        for _, anchor in ipairs(note.anchors) do
          local source_win = self.snapshot and self.snapshot.windows[anchor.side]
          if source_win and api.nvim_win_is_valid(source_win) then
            -- A range often starts at an unchanged block header. Put its diff
            -- summary beside the actual change, while retaining the full range
            -- for references/details. Unchanged notes keep their original start.
            local row = anchor.start_line
            if note.kind ~= "overview" and vim.wo[source_win].diff then
              row = api.nvim_win_call(source_win, function()
                for line = anchor.start_line, math.min(anchor.end_line, api.nvim_buf_line_count(0)) do
                  if vim.fn.diff_hlID(line, 1) ~= 0 then return line end
                end
                return anchor.start_line
              end)
            end
            if source_win == self.source then projected = { row = math.min(count, row) }; break end
            foreign = foreign or { win = source_win, row = row }
          end
        end
        if not projected and foreign then
          local coordinate = self:coordinates(foreign.win)[foreign.row]
          if coordinate then projected = self:locate(coordinate) end
        end
        if projected then
          local first, last = math.huge, 0
          for _, range in ipairs(ranges) do first = math.min(first, range[1]); last = math.max(last, range[2]) end
          entries[#entries + 1] = { id = index, note = note, ranges = ranges, span = last - first,
            coordinate = self:coordinates(self.source)[projected.row] + (projected.offset or 0) }
        end
      end
    end
    local rank = { documented = 1, inferred = 2, unknown = 3 }
    table.sort(entries, function(a, b)
      if a.coordinate ~= b.coordinate then return a.coordinate < b.coordinate end
      if (a.note.kind == "overview") ~= (b.note.kind == "overview") then return a.note.kind == "overview" end
      if a.span ~= b.span then return a.span < b.span end
      local ar, br = rank[a.note.intent_basis] or 3, rank[b.note.intent_basis] or 3
      if ar ~= br then return ar < br end
      return a.id < b.id
    end)
    -- Reserve every primary annotation position before moving colliding notes.
    -- Prefer existing comparison rows inside anchors. Exhausted ranges spill
    -- into free annotation rows below, never stealing another primary position
    -- or rewriting source anchors/geometry.
    local occupied, extra = {}, {}
    local coordinates = self:coordinates(self.source)
    local comparison_end = coordinates[count] + self.eof_fill
    for _, entry in ipairs(entries) do
      if occupied[entry.coordinate] then extra[#extra + 1] = entry
      else occupied[entry.coordinate] = true end
    end
    for _, entry in ipairs(extra) do
      local target
      for _, range in ipairs(entry.ranges) do
        local candidate = math.max(entry.coordinate + 1, range[1])
        while candidate <= range[2] and occupied[candidate] do candidate = candidate + 1 end
        if candidate <= range[2] then target = math.min(target or candidate, candidate) end
      end
      if not target then
        -- Outside anchors, prefer cursor-addressable rows rather than sharing
        -- the native cursor of an unrelated diff-filler/primary annotation.
        local projected = self:locate(entry.coordinate + 1)
        local row = projected.eof and count + 1 or projected.row
        repeat
          target = row <= count and coordinates[row] or comparison_end + row - count
          row = row + 1
        until not occupied[target]
        entry.target = entry.coordinate
      end
      entry.coordinate = target; occupied[target] = true
    end
    table.sort(entries, function(a, b) return a.coordinate < b.coordinate end)
    for _, entry in ipairs(entries) do
      local text, items = "", {}
      local function append(value, hl)
        local first = #text
        text = text .. value; items[#items + 1] = { first, #text, hl }
      end
      local projected = entry.coordinate <= comparison_end and self:locate(entry.coordinate)
        or { row = count + entry.coordinate - comparison_end }
      for row = #lines + 1, projected.row do
        lines[row], spans[row], self.rows[row] = "", {}, {}
      end
      self.locations[entry.id] = projected
      table.insert(self.rows[projected.row], entry.id)
      if entry.target and not projected.offset then self.overflow[projected.row] = entry.target end
      local ref = reference(entry.note)
      local cue = intent[entry.note.intent_basis] or intent.unknown
      local prefix = "▎ " .. cue[1] .. " "
      local body = shorten(single_line(entry.note.summary) .. " [+]",
        math.max(6, width - vim.fn.strdisplaywidth(ref .. prefix)))
      local tail = body:find(" …", 1, true) or body:find(" [+]", 1, true) or #body + 1
      append(prefix, cue[2])
      append(body:sub(1, tail - 1), "ExplainrSummary")
      append(body:sub(tail), "ExplainrDetailCue")
      if projected.offset then
        self.filler[projected.row] = self.filler[projected.row] or {}
        self.filler_refs[projected.row] = self.filler_refs[projected.row] or {}
        local filler = projected.eof and self.eof or self.filler[projected.row]
        local refs = projected.eof and self.eof_refs or self.filler_refs[projected.row]
        filler[projected.offset], refs[projected.offset] = text, ref
      else
        lines[projected.row], spans[projected.row], self.references[projected.row] = text, items, ref
      end
    end
    self.populated, self.note_order = {}, {}
    for row in ipairs(lines) do
      if #self.rows[row] > 0 then
        self.populated[#self.populated + 1] = row
        vim.list_extend(self.note_order, self.rows[row])
      end
      lines[row] = shorten(lines[row], math.max(6, width - vim.fn.strdisplaywidth(self.references[row] or "")))
    end
    local content = #lines > 0 and lines or { "" }
    if not vim.deep_equal(content, api.nvim_buf_get_lines(self.buf, 0, -1, false)) then
      vim.bo[self.buf].modifiable = true
      api.nvim_buf_set_lines(self.buf, 0, -1, false, content)
      vim.bo[self.buf].modifiable = false
    end
    api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
    for row, items in ipairs(spans) do
      for _, span in ipairs(items) do mark(self.buf, row - 1, span[1], math.min(span[2], #lines[row]), span[3]) end
    end
    self.lines, self.line_spans = lines, spans
    -- Expanded navigation rebuilds the hidden overview without displaying it
    -- or applying overview window options/decorations to the Markdown buffer.
    if self.detail_win then self.rendering = false; return end
    local aligned = self:align()
    self.rendering = false
    if aligned == false then self:render() end
  end

  function pane:set(value, status)
    if self.closed then return end
    self.selection = nil
    self:back(true)
    self.result, self.status = value, status or "Ready"
    self:animate()
    self:render()
  end

  -- Detail context owns exact comparison coordinates; prose owns a bounded
  -- display position. Both cursor motion and explicit collapse use this target.
  function pane:detail_target()
    local layout = self.detail_layout
    local context = layout.rows[api.nvim_win_get_cursor(self.win)[1]]
    if context and context.item then
      local item = context.item
      local last = item.line <= self.source_count and api.nvim_win_call(layout.source,
        function() return vim.fn.foldclosedend(item.line) end) or -1
      if not item.filler and ((last >= 0) ~= (item.folded == true) or last >= 0 and last ~= item.last) then
        -- A programmatic/off-screen fold change may have no input event.
        -- Refresh at the addressed target before trusting retained EOF rows.
        self.detail_context_cache = nil
        self:place_detail()
        return self:detail_target()
      end
      local coordinate = (self.overflow[item.line] or self:coordinates(layout.source)[item.line]) + (item.offset or 0)
      local candidate, target = layout.source, self:locate(coordinate, layout.source)
      if target.offset then
        for source_win in pairs(self:windows()) do
          local real = self:locate(coordinate, source_win)
          if not real.offset then candidate, target = source_win, real; break end
        end
      end
      local first = api.nvim_win_call(candidate, function() return vim.fn.foldclosed(target.row) end)
      return { win = candidate, line = first >= 0 and first or target.row }
    end
    local screen_row = api.nvim_win_call(self.win, vim.fn.winline)
    local sources = { layout.source }
    for candidate in pairs(self:windows()) do
      if candidate ~= layout.source then sources[#sources + 1] = candidate end
    end
    local target, distance, display_row
    for _, candidate in ipairs(sources) do
      local coordinates = self:coordinates(candidate)
      for row, item in ipairs(M.project(candidate)) do
        if not item.empty and not item.filler then
          local first, last = coordinates[item.line], coordinates[item.last]
          for _, range in ipairs(layout.ranges) do
            if first <= range[2] and last >= range[1] then
              local delta = math.abs(row - screen_row)
              if not distance or delta < distance or delta == distance and row < display_row then
                target, distance, display_row = { win = candidate, line = item.line }, delta, row
              end
              break
            end
          end
        end
      end
    end
    return target
  end

  function pane:select_source(target)
    local syncing, views = self.syncing, {}
    self.syncing = true
    for candidate in pairs(self:windows()) do views[candidate] = api.nvim_win_call(candidate, vim.fn.winsaveview) end
    local column = api.nvim_win_get_cursor(target.win)[2]
    local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(target.win), target.line - 1, target.line, false)[1]
    api.nvim_win_set_cursor(target.win, { target.line, math.min(column, math.max(0, #text - 1)) })
    self:sync_sources(target.line, target.win)
    -- Selection must not add a scrolloff/diff-bind viewport shift on top of
    -- scrolling already synchronized by the detail reader.
    for candidate, view in pairs(views) do
      local selected = api.nvim_win_get_cursor(candidate)
      view.lnum, view.col = selected[1], selected[2]
      api.nvim_win_call(candidate, function() vim.fn.winrestview(view) end)
      self.scroll_views[candidate] = api.nvim_win_call(candidate, vim.fn.winsaveview)
    end
    self.syncing = syncing
  end

  function pane:back(replacing)
    if self.closed or not self.detail_win then return end
    replacing = replacing or not self:detail_valid()
    self.display_generation = (self.display_generation or 0) + 1
    clear_detail_marks()
    local saved, detail = self.overview, self.detail_buf
    local target, row
    if not replacing then
      local layout = self.detail_layout
      local view = api.nvim_win_call(self.win, vim.fn.winsaveview)
      local moved = layout.reading or not vim.deep_equal(view, layout.initial)
      if moved then target = self:detail_target() end
      target = target or { win = self.source, line = api.nvim_win_get_cursor(self.source)[1] }
      self:select_source(target)
      if self.source ~= target.win then self.source, self.folds = target.win, {} end
      row = target.line
      -- An untouched overflow summary still represents this source position.
      local overflow = not moved and self.overflow[saved.view.lnum]
      if overflow and self:locate(overflow).row == row then row = saved.view.lnum end
      self.syncing = true
    end
    -- Clear the guard only after swapping: BufWinEnter must not synchronize a
    -- Markdown cursor against code, nor wipe our hidden summary.
    if api.nvim_win_is_valid(self.win) and api.nvim_buf_is_valid(self.buf) then
      api.nvim_win_set_buf(self.win, self.buf)
      for name, value in pairs(saved.options) do vim.wo[self.win][name] = value end
      api.nvim_win_call(self.win, function()
        vim.cmd("silent! normal! zE")
        for first, last in pairs(self.folds) do vim.cmd(string.format("%d,%dfold", first, last)) end
        if replacing then vim.fn.winrestview(saved.view)
        else api.nvim_win_set_cursor(self.win, { math.min(row, api.nvim_buf_line_count(self.buf)), 0 }) end
      end)
    end
    self.detail_win, self.detail_buf, self.detail_index, self.overview = nil, nil, nil, nil
    self.detail_layout = nil
    self.detail_context_cache = nil
    self.detail_folds_dirty, self.fold_prefix = nil, nil
    self.focus_ids = nil
    if detail and api.nvim_buf_is_valid(detail) then api.nvim_buf_delete(detail, { force = true }) end
    -- A new result (including invalidation on a Diffview file switch) must
    -- rebuild geometry before focusing; the old projection belongs to old text.
    if not replacing then
      self:render()
      self.syncing = false
    end
  end

  -- Context is display-only, but its real blank rows own exact source targets.
  -- Cache geometry once, independently of the viewport. Scrolling changes an
  -- origin index, not every EOF target. render() invalidates on geometry/result
  -- changes; reader width and range changes are checked here as well.
  function pane:detail_context(ranges, required_row)
    self.projection = self:project()
    local width = math.max(1, api.nvim_win_get_width(self.win) - 2)
    local info = vim.fn.getwininfo(self.source)[1]
    local tick = api.nvim_buf_get_changedtick(info.bufnr)
    local view = api.nvim_win_call(self.source, vim.fn.winsaveview)
    local skipped = skipped_rows(self.source, view)
    local cache = self.detail_context_cache
    if cache and (cache.source ~= self.source or cache.buf ~= info.bufnr or cache.tick ~= tick
        or cache.source_width ~= info.width - info.textoff or cache.width ~= width or not vim.deep_equal(cache.ranges, ranges)) then
      cache = nil
    end
    if cache and required_row and not cache.lines[required_row] then cache = nil end
    if cache then
      -- Fold changes can precede the scheduled rebuild. Validate the visible
      -- slice so an opened fold never leaves the new topline without a target.
      local origin = cache.lines[view.topline]
      if origin then
        origin = origin - view.topfill + skipped
        for row, item in ipairs(self.projection) do
          if item.empty then break end
          local context = cache.rows[origin + row - 1]
          if not context or not vim.deep_equal(context.item, item) then cache = nil; break end
        end
      else cache = nil end
    end
    if not cache then
      cache = { source = self.source, buf = info.bufnr, tick = tick, source_width = info.width - info.textoff,
        width = width, ranges = vim.deepcopy(ranges), rows = {}, lines = {}, populated = {}, anchor_end = 0 }
      local coordinates, seen = self:coordinates(self.source), {}
      for row, item in ipairs(self:project(true, true)) do
        if item.empty then break end
        local first = (self.overflow[item.line] or coordinates[item.line]) + (item.offset or 0)
        local last = item.folded and coordinates[item.last] or first
        local active = false
        for _, range in ipairs(ranges) do
          if first <= range[2] and last >= range[1] then active, cache.anchor_end = true, row; break end
        end
        local text = ""
        if item.eof then text = (self.eof_refs[item.offset] or "") .. (self.eof[item.offset] or "")
        elseif item.filler then
          text = (self.filler_refs[item.line] and self.filler_refs[item.line][item.offset] or "")
            .. (self.filler[item.line] and self.filler[item.line][item.offset] or "")
        elseif not seen[item.line] then
          text = item.folded and self:fold_label(item.line, item.last)
            or (self.references[item.line] or "") .. self.lines[item.line]
          seen[item.line], cache.lines[item.line] = true, row
        end
        text = shorten(text, width)
        local hl = active and { "ExplainrDetailContext", "ExplainrDetailActive" } or "ExplainrDetailContext"
        if text ~= "" then cache.populated[#cache.populated + 1] = row end
        cache.rows[row] = { item = item, coordinate = first, active = active, populated = text ~= "", chunks = { { text, hl },
          { string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text))), hl } } }
      end
      self.detail_context_cache = cache
    end
    local origin = cache.lines[view.topline] - view.topfill + skipped
    return cache.rows, math.max(0, cache.anchor_end - origin + 1), origin
  end

  -- Only visible context needs extmarks or gutter entries. Off-screen blank
  -- rows remain cursor-addressable through layout.rows' lazy source mapping.
  function pane:decorate_detail_context()
    local layout = self.detail_layout
    for _, id in ipairs(layout.marks) do api.nvim_buf_del_extmark(self.detail_buf, ns, id) end
    layout.marks = {}
    local view = api.nvim_win_call(self.win, vim.fn.winsaveview)
    local height = vim.fn.getwininfo(self.win)[1].height
    local active = {}
    for row = view.topline, math.min(api.nvim_buf_line_count(self.detail_buf), view.topline + height) do
      local context = layout.rows[row]
      if row >= layout.first and row <= layout.last or context and context.active then active[tostring(row)] = 1 end
      if context then
        local chunks = context.chunks
        layout.marks[#layout.marks + 1] = api.nvim_buf_set_extmark(self.detail_buf, ns, row - 1, 0, {
          end_row = row, end_col = 0, hl_group = chunks[1][2], hl_eol = true, priority = 130 })
        layout.marks[#layout.marks + 1] = api.nvim_buf_set_extmark(self.detail_buf, ns, row - 1, 0, {
          virt_text = chunks, virt_text_pos = "overlay", priority = 140 })
      end
    end
    vim.b[self.detail_buf].explainr_detail_active = active
  end

  function pane:detail_position()
    local location = self.locations[self.detail_index]
    local row, offset = math.min(location.row, self.source_count), location.offset or 0
    local first = api.nvim_win_call(self.source, function() return vim.fn.foldclosed(row) end)
    if first >= 0 then row = first end
    local rows, _, origin = self:detail_context(self.detail_layout.ranges, row)
    local line_rows = self.detail_context_cache.lines
    -- Overflow indices already follow the final wrap and every EOF deletion.
    local natural = line_rows[location.row > self.source_count and location.row or row] - origin + 1 + offset
    return rows, line_rows, origin, natural
  end

  function pane:place_detail()
    local layout = self.detail_layout
    if not layout or self.closed or not api.nvim_win_is_valid(self.win) or not api.nvim_win_is_valid(self.source) then return end
    if not self:detail_valid() then return end
    local syncing = self.syncing
    self.syncing = true
    local view = api.nvim_win_call(self.win, vim.fn.winsaveview)
    local untouched = not layout.reading and vim.deep_equal(view, layout.initial)
    local cursor_offset, top_offset = view.lnum - layout.first, view.topline - layout.first
    local context_cursor = layout.rows[view.lnum]
    local count = layout.last - layout.first + 1
    local card_height = api.nvim_win_text_height(self.win, { start_row = layout.first - 1, end_row = layout.last - 1 }).all
    local height = vim.fn.getwininfo(self.win)[1].height
    local rows, line_rows, origin, natural = self:detail_position()
    layout.natural, layout.card_height = natural, card_height
    local leading_count = math.max(0, math.min(height - card_height, natural - 1))
    local trimmed = math.max(0, math.min(#rows - origin + 1, natural - 1) - leading_count)
    local tail_origin = origin + trimmed + leading_count + card_height
    -- Retain a neighbor covered by the prose, without scanning the EOF suffix.
    local populated = self.detail_context_cache.populated
    local low, high = 1, #populated + 1
    local next_row = math.max(origin, origin + natural)
    while low < high do
      local middle = math.floor((low + high) / 2)
      if populated[middle] < next_row then low = middle + 1 else high = middle end
    end
    if populated[low] then tail_origin = math.min(tail_origin, populated[low]) end
    local trailing_count = math.max(0, #rows - tail_origin + 1)
    vim.bo[self.detail_buf].modifiable = true
    -- Resize blank context incrementally, without rewriting the retained EOF
    -- suffix or allocating a replacement table for every off-screen row.
    local trailing = api.nvim_buf_line_count(self.detail_buf) - layout.last
    if trailing_count < trailing then
      api.nvim_buf_set_lines(self.detail_buf, layout.last + trailing_count, -1, false, {})
    elseif trailing_count > trailing then
      api.nvim_buf_set_lines(self.detail_buf, -1, -1, false, vim.fn["repeat"]({ "" }, trailing_count - trailing))
    end
    if leading_count ~= layout.first - 1 then
      api.nvim_buf_set_lines(self.detail_buf, 0, layout.first - 1, false, vim.fn["repeat"]({ "" }, leading_count))
    end
    vim.bo[self.detail_buf].modifiable = false
    layout.first, layout.last = leading_count + 1, leading_count + count
    local last = layout.last
    layout.rows = setmetatable({}, { __index = function(_, destination)
      if destination >= 1 and destination <= leading_count then return rows[origin + trimmed + destination - 1] end
      if destination > last then return rows[tail_origin + destination - last - 1] end
    end })
    layout.source = self.source
    self.overview.context = {}
    for index = 1, leading_count do self.overview.context[index] = layout.rows[index].chunks end
    view.lnum = layout.first + math.max(0, math.min(count - 1, cursor_offset))
    if context_cursor then
      local target = self:locate(context_cursor.coordinate, self.source)
      local row = target.row
      local fold = api.nvim_win_call(self.source, function() return vim.fn.foldclosed(row) end)
      if fold >= 0 then row = fold end
      local index = line_rows[row]
      -- Side switches and newly closed folds can remove an old context target.
      if index then
        index = index + (target.offset or 0)
        if target.eof then index = line_rows[row] + api.nvim_win_text_height(self.source,
          { start_row = row - 1, end_row = row - 1, start_vcol = 0 }).all + target.offset - 1 end
        local destination = index < tail_origin and index - origin - trimmed + 1 or last + index - tail_origin + 1
        local context = layout.rows[destination]
        if context and (context.coordinate == context_cursor.coordinate or context.item.folded) then view.lnum = destination end
      end
    end
    if card_height > height then
      view.topline = layout.first + math.max(0, math.min(count - 1, top_offset))
    else view.topline, view.skipcol = 1, 0 end
    view.topfill = 0
    api.nvim_win_call(self.win, function() vim.fn.winrestview(view) end)
    self:decorate_detail_context()
    for candidate in pairs(self:windows()) do self.scroll_views[candidate] = api.nvim_win_call(candidate, vim.fn.winsaveview) end
    self.scroll_views[self.win] = api.nvim_win_call(self.win, vim.fn.winsaveview)
    if untouched then layout.initial = vim.deepcopy(self.scroll_views[self.win]) end
    self.syncing = syncing
  end

  function pane:detail_reflow()
    local layout = self.detail_layout
    if not layout or not layout.card_height or not self:detail_valid() then return false end
    local height = api.nvim_win_text_height(self.win, { start_row = layout.first - 1, end_row = layout.last - 1 }).all
    if height == layout.card_height then return false end
    -- Decoration/concealment changes are not a user scroll. Rebaseline native
    -- viewport corrections without forwarding them back into the sources.
    self:place_detail()
    return true
  end

  function pane:detail(index)
    if self.closed or not self.result then return end
    self.selection = nil
    index = type(index) == "number" and index or nil
    if index and not self.result.notes[index] then return end
    local ids = index and { index } or {}
    if not index then
      if self.detail_win then return end
      ids = self:note_ids()
      if #ids == 0 then
        local row = api.nvim_win_get_cursor(self.win)[1]
        local last = api.nvim_win_call(self.win, function() return vim.fn.foldclosedend(row) end)
        local coordinates = self:coordinates(self.source)
        local first, finish = coordinates[row], coordinates[last >= row and last or row]
        local locals, overviews = {}, {}
        for _, id in ipairs(self.note_order) do
          local note = self.result.notes[id]
          for _, range in ipairs(self:ranges(note.anchors, self.snapshot.windows)) do
            if first and finish and first <= range[2] and finish >= range[1] then
              local candidates = note.kind == "overview" and overviews or locals
              candidates[#candidates + 1] = id
              break
            end
          end
        end
        if #locals == 1 then ids = locals
        else
          ids = vim.list_extend(locals, overviews)
          if #ids > 1 then
            local selection, result, snapshot = {}, self.result, self.snapshot
            self.selection = selection
            vim.ui.select(ids, { prompt = "Expand explanation:", format_item = function(id)
              local note = result.notes[id]
              return (note.kind == "overview" and "Overview · " or "") .. reference(note) .. single_line(note.summary)
            end }, function(id)
              if self.closed or self.selection ~= selection or self.result ~= result or self.snapshot ~= snapshot
                  or self.detail_win or api.nvim_get_current_win() ~= self.win then return end
              self.selection = nil
              if id then self:detail(id) end
            end)
            return
          end
        end
      end
    end
    if #ids == 0 then return end
    local navigating = self.detail_win ~= nil
    if navigating then
      local location = self.locations[index]
      local candidate, row = self.source, location.row
      if self.overflow[row] then row = self:locate(self.overflow[row]).row end
      if location.offset then
        local coordinate = self:coordinates(candidate)[row] + location.offset
        for source_win in pairs(self:windows()) do
          local target = self:locate(coordinate, source_win)
          if not target.offset then candidate, row = source_win, target.row; break end
        end
      end
      local first = api.nvim_win_call(candidate, function() return vim.fn.foldclosed(row) end)
      api.nvim_win_set_cursor(candidate, { first >= 0 and first or row, 0 })
      api.nvim_win_call(candidate, function() vim.cmd.normal({ "zz", bang = true }) end)
      if self.source ~= candidate then self.folds = {} end
      self.source = candidate
      self:sync_sources(api.nvim_win_get_cursor(candidate)[1])
      self:render()
      self.scroll_views = {}
      for source_win in pairs(self:windows()) do
        self.scroll_views[source_win] = api.nvim_win_call(source_win, vim.fn.winsaveview)
      end
      self.overview.view = api.nvim_win_call(candidate, vim.fn.winsaveview)
      self.overview.view.lnum = self.locations[index].row
      self.overview.view.col, self.overview.view.leftcol, self.overview.view.skipcol = 0, 0, 0
      self.overview.scrolled = true
    end
    self.display_generation = (self.display_generation or 0) + 1
    self:focus(true)
    if not self.overview then
      self.overview = { view = api.nvim_win_call(self.win, vim.fn.winsaveview), options = {} }
      for _, name in ipairs({ "wrap", "linebreak", "foldenable", "conceallevel", "concealcursor", "winbar",
        "signcolumn", "statuscolumn", "winhighlight" }) do
        self.overview.options[name] = vim.wo[self.win][name]
      end
    end
    -- Capture the source display rows, including folds, wraps and diff filler.
    -- Entry navigation has already synchronized the new collapse cursor/view.
    self.projection = self:project()
    local ranges = {}
    for _, id in ipairs(ids) do
      vim.list_extend(ranges, self:ranges(self.result.notes[id].anchors, self.snapshot.windows))
    end
    local context_rows, anchor_end, origin = self:detail_context(ranges)
    context_rows = vim.list_slice(context_rows, origin)
    local context, following, opening, next_note = {}, {}, nil, nil
    local location = self.locations[ids[1]]
    for row, projected in ipairs(context_rows) do
      local item = projected.item
      if not opening and location and (location.offset and item.line == location.row
          and item.offset == location.offset and item.eof == location.eof
        or not location.offset and not item.filler and item.line <= location.row and item.last >= location.row) then
        opening = row
      end
      if not opening then
        local chunks = vim.deepcopy(projected.chunks)
        if projected.active then
          chunks[1] = { chunks[1][1] .. chunks[2][1], { "Normal", "ExplainrDetailActive" } }
          chunks[2] = { "", "ExplainrDetailContext" }
        end
        context[#context + 1] = chunks
      elseif row > opening then
        -- Neighboring summaries stay dimmed, but must not cut off the active
        -- background/rail when they lie inside this explanation's anchors.
        following[row] = projected.chunks
        if projected.populated and not next_note then next_note = row end
      end
    end
    if not opening then
      -- Expanding from an off-screen anchor uses the top-edge fallback, but
      -- still owns the complete following context and its actual eligibility.
      for row, projected in ipairs(context_rows) do
        following[row] = projected.chunks
        if projected.populated and not next_note then next_note = row end
      end
    end
    -- Off-screen entries have no visible expansion position; start at the top.
    self.overview.context = opening and context or {}
    self.detail_win, self.detail_index = self.win, ids[1]
    self:source_focus(ids)
    local lines, headers = {}, {}
    for _, id in ipairs(ids) do
      local note = self.result.notes[id]
      local cue, ref = intent[note.intent_basis] or intent.unknown, reference(note)
      local prefix = "▎ " .. cue[1] .. " "
      headers[#headers + 1] = { row = #lines, ref = ref, prefix = #prefix, hl = cue[2] }
      lines[#lines + 1] = prefix .. single_line(note.summary)
      lines[#lines + 1] = "**Intent basis:** " .. note.intent_basis .. " · `" .. note.anchors[1].path .. "`"
      lines[#lines + 1] = ""
      headers[#headers].body = #lines
      vim.list_extend(lines, vim.split(note.detail, "\n", { plain = true }))
      lines[#lines + 1] = ""
    end
    local detail = self.detail_buf or api.nvim_create_buf(false, true)
    api.nvim_buf_clear_namespace(detail, ns, 0, -1)
    vim.bo[detail].modifiable = true
    api.nvim_buf_set_lines(detail, 0, -1, false, lines)
    vim.bo[detail].modifiable = false
    if not navigating then
      vim.bo[detail].bufhidden = "wipe"
      vim.bo[detail].filetype = "explainr"
      start_markdown(detail)
    end
    for row, line in ipairs(lines) do
      -- Base focus tint must not override syntax highlighting.
      api.nvim_buf_set_extmark(detail, ns, row - 1, 0, { end_row = row, end_col = 0,
        hl_group = "ExplainrDetailActive", hl_eol = true, priority = 0 })
      if line:match("^#") then mark(detail, row - 1, 0, #line, "ExplainrHeading")
      elseif line:match("^%*%*Intent") then
        mark(detail, row - 1, 0, #line, "ExplainrMetadata")
        api.nvim_buf_set_extmark(detail, ns, row - 1, 0, { end_row = row, end_col = 0,
          hl_group = "ExplainrDetailActive", hl_eol = true, priority = 130 })
      end
    end
    for _, header in ipairs(headers) do
      local line = lines[header.row + 1]
      mark(detail, header.row, 0, header.prefix, header.hl)
      mark(detail, header.row, header.prefix, #line, "ExplainrSummary")
      -- Semantic/theme backgrounds must not cut holes in the card header.
      api.nvim_buf_set_extmark(detail, ns, header.row, 0, { end_row = header.row + 1, end_col = 0,
        hl_group = "ExplainrDetailActive", hl_eol = true, priority = 130 })
      -- Match overview controls exactly; Markdown must not conceal them as links.
      api.nvim_buf_set_extmark(detail, ns, header.row, 0, {
        virt_text = { { header.ref, { "ExplainrMetadata", "ExplainrDetailActive" } } }, virt_text_pos = "inline", priority = 120,
      })
      api.nvim_buf_set_extmark(detail, ns, header.row, #line, {
        virt_text = { { " [−]", { "ExplainrDetailCue", "ExplainrDetailActive" } } }, virt_text_pos = "inline", priority = 120,
      })
    end
    local context_mark
    if #self.overview.context > 0 then
      context_mark = api.nvim_buf_set_extmark(detail, ns, 0, 0, { virt_lines = self.overview.context, virt_lines_above = true })
    end
    self.detail_buf = detail
    if not navigating then
      api.nvim_win_set_buf(self.win, detail)
      api.nvim_set_current_win(self.win)
    end
    vim.wo[self.win].foldenable = false
    local mappings = {}
    for from, to in self.overview.options.winhighlight:gmatch("([^,:]+):([^,]+)") do mappings[from] = to end
    -- Wrapped linebreak gaps use the window background, not hl_eol. Keep it
    -- active while explicit dimmed context and EndOfBuffer retain the backdrop.
    for _, name in ipairs({ "Normal", "NormalNC" }) do mappings[name] = "ExplainrDetailActive" end
    for _, name in ipairs({ "EndOfBuffer", "SignColumn" }) do mappings[name] = "ExplainrDetailBackdrop" end
    local highlights = {}
    for from, to in pairs(mappings) do highlights[#highlights + 1] = from .. ":" .. to end
    vim.wo[self.win].winhighlight = table.concat(highlights, ",")
    vim.wo[self.win].signcolumn = "yes:1"
    -- A native gutter repeats on wrapped display rows too, unlike sign extmarks.
    -- Both views reserve a rail and one space: expansion never shifts text.
    -- Give the gutter its own background so the content tint cannot spill into
    -- the rail/padding, including wrapped rows.
    -- Buffer transitions can evaluate the gutter before detail data exists.
    -- Do not make it the window's default for newly displayed buffers.
    vim.wo[self.win][0].statuscolumn = "%#ExplainrDetailGutter#%{exists('b:explainr_detail_active') && get(b:explainr_detail_active, string(v:lnum), 0) ? '▎ ' : '  '}"
    self:header(ids)
    vim.wo[self.detail_win].wrap = true
    vim.wo[self.detail_win].linebreak = true
    vim.wo[self.detail_win].conceallevel = 0
    -- Near the bottom, make room for the first body line instead of expanding
    -- entirely below the viewport. Trim only leading context, never move code.
    local height = api.nvim_win_text_height(self.win, { start_row = 0, end_row = headers[1].body }).all
      - #self.overview.context
    local keep = math.max(0, vim.fn.getwininfo(self.win)[1].height - height)
    if #self.overview.context > keep then
      self.overview.context = vim.list_slice(self.overview.context, #self.overview.context - keep + 1)
      api.nvim_buf_set_extmark(detail, ns, 0, 0, { id = context_mark,
        virt_lines = self.overview.context, virt_lines_above = true })
    end
    -- Keep the visible anchored extent without clipping a long explanation.
    local card_height = api.nvim_win_text_height(self.win, { start_row = 0, end_row = #lines - 1 }).all
    local trimmed = opening and opening - 1 - #self.overview.context or 0
    local tail_start = math.max(anchor_end + 1, card_height + trimmed + 1)
    -- Never consume a neighboring note, even inside overlapping anchors or
    -- under a long detail. Keep its source row when space allows; otherwise
    -- place it immediately below the card.
    if next_note then tail_start = math.min(tail_start, next_note) end
    local trailing, tail_rows = {}, {}
    for row = card_height + trimmed + 1, tail_start - 1 do
      local projected = context_rows[row]
      trailing[#trailing + 1] = { { "", projected and projected.active
        and { "ExplainrDetailContext", "ExplainrDetailActive" } or "ExplainrDetailContext" } }
      tail_rows[#trailing] = row
    end
    for row = tail_start, #context_rows do
      if following[row] then
        trailing[#trailing + 1] = following[row]
        tail_rows[#trailing] = row
      end
    end

    -- Virtual lines cannot receive a cursor. Give each context/continuation
    -- row a real blank line, with a display-only label so Markdown does not
    -- parse or wrap neighboring summaries. Only prose is Markdown content.
    local leading, tail = {}, {}
    local layout = { source = self.source, rows = {}, marks = {}, buffers = {}, first = #self.overview.context + 1,
      last = #self.overview.context + #lines, ranges = ranges, ids = ids }
    for candidate in pairs(self:windows()) do layout.buffers[candidate] = api.nvim_win_get_buf(candidate) end
    local function context_row(row, chunks, projected)
      local hl = chunks[1][2]
      local focused = hl == "ExplainrDetailActive" or type(hl) == "table"
      layout.rows[row] = { item = context_rows[projected] and context_rows[projected].item,
        coordinate = context_rows[projected] and context_rows[projected].coordinate, active = focused, chunks = chunks }
    end
    for row, chunks in ipairs(self.overview.context) do
      leading[row] = ""
      context_row(row, chunks, trimmed + row)
    end
    for row, chunks in ipairs(trailing) do
      tail[row] = ""
      context_row(layout.last + row, chunks, tail_rows[row])
    end
    if context_mark then api.nvim_buf_del_extmark(detail, ns, context_mark) end
    vim.bo[detail].modifiable = true
    api.nvim_buf_set_lines(detail, #lines, #lines, false, tail)
    api.nvim_buf_set_lines(detail, 0, 0, false, leading)
    vim.bo[detail].modifiable = false
    self.detail_layout = layout
    api.nvim_win_call(self.win, function()
      vim.fn.winrestview({ topline = 1, topfill = 0, lnum = layout.first, col = 0 })
    end)
    self:decorate_detail_context()
    layout.card_height = api.nvim_win_text_height(self.win, { start_row = layout.first - 1, end_row = layout.last - 1 }).all
    self.scroll_views[self.win] = api.nvim_win_call(self.win, vim.fn.winsaveview)
    layout.initial = vim.deepcopy(self.scroll_views[self.win])
    if navigating then return end
    local function close_detail()
      self:back()
      if api.nvim_win_is_valid(self.win) then api.nvim_set_current_win(self.win) end
    end
    if keymaps then keymaps(detail) end
    vim.keymap.set("n", "<Esc>", close_detail, { buffer = detail })
    vim.keymap.set("n", "q", close_detail, { buffer = detail })
    vim.keymap.set("n", "K", close_detail, { buffer = detail })
    vim.keymap.set("n", "<CR>", close_detail, { buffer = detail })
    for _, lhs in ipairs({ "<C-e>", "<C-y>" }) do
      local keys = api.nvim_replace_termcodes(lhs, true, false, true)
      vim.keymap.set("n", lhs, function() self:scroll(vim.v.count1 .. keys, self.win, lhs == "<C-y>") end, { buffer = detail })
    end
    for _, lhs in ipairs({ "j", "k" }) do
      vim.keymap.set("n", lhs, function()
        local count = vim.v.count1
        -- Above the summary's first display row, scroll code instead of
        -- entering stale leading context. A clipped later wrap is still prose.
        if lhs == "k" and api.nvim_win_get_cursor(self.win)[1] == self.detail_layout.first
            and api.nvim_win_call(self.win, function()
              return vim.fn.winline() == 1 and vim.fn.winsaveview().skipcol == 0
            end) then
          self:scroll(api.nvim_replace_termcodes(count .. "<C-y>", true, false, true), self.win)
        else
          api.nvim_win_call(self.win, function()
            vim.cmd.normal({ count .. "g" .. lhs, bang = true })
            -- Settle native smoothscroll/skipcol before forwarding the viewport
            -- delta; a later screen-row query can otherwise shift it again.
            vim.fn.winline()
          end)
          self:sync(self.win)
        end
      end, { buffer = detail })
    end
    for lhs, direction in pairs({ n = 1, p = -1, N = -1 }) do
      vim.keymap.set("n", lhs, function()
        local position = 1
        for i, id in ipairs(self.note_order) do if id == self.detail_index then position = i; break end end
        local next_position = math.max(1, math.min(#self.note_order, position + direction * vim.v.count1))
        if next_position == position then return end
        self:detail(self.note_order[next_position])
      end, { buffer = detail })
    end
  end

  function pane:scroll(keys, from, escape)
    if self.closed or self.syncing or not api.nvim_win_is_valid(self.source) or not api.nvim_win_is_valid(self.win) then return end
    if not self:detail_valid() then return end
    from = from or self.source
    if from == self.win and not self.detail_win then self:sync(from); return end
    if from == self.win and self:detail_reflow() and not keys then return end
    if escape and self.detail_layout then
      local layout = self.detail_layout
      local view = api.nvim_win_call(self.win, vim.fn.winsaveview)
      local height = vim.fn.getwininfo(self.win)[1].height
      local count = tonumber(keys:match("^(%d*)\25$")) or 1
      local _, _, _, natural = self:detail_position()
      local room = math.max(0, height - layout.card_height + 1 - natural)
      if layout.card_height < height and view.lnum >= layout.first and view.lnum <= layout.last
          and view.topline <= layout.first and view.skipcol == 0 and count > room then
        -- Consume only the portion before the boundary, never the blocked
        -- step. k's top-edge shortcut does not request this reader-only exit.
        if room > 0 then self:scroll(room .. "\25", from) end
        local _, _, _, settled = self:detail_position()
        local source_view = api.nvim_win_call(self.source, vim.fn.winsaveview)
        if settled >= height - layout.card_height + 1
            and (source_view.topline > 1 or source_view.topfill > 0 or source_view.skipcol > 0) then
          self:place_detail()
          local context = layout.rows[layout.first - 1]
          if context and context.item then
            view = api.nvim_win_call(self.win, vim.fn.winsaveview)
            view.lnum, view.col = layout.first - 1, 0
            api.nvim_win_call(self.win, function() vim.fn.winrestview(view) end)
            layout.reading = true
            if context.active then
              self:select_source(self:detail_target())
              self:sync(self.win)
            else
              self:back()
            end
            return
          end
        end
        if room > 0 then return end -- Native BOF can be reached before the card edge.
      end
    end
    self.syncing = true
    local before = self.scroll_views and self.scroll_views[from] or api.nvim_win_call(from, vim.fn.winsaveview)
    if keys then api.nvim_win_call(from, function() vim.cmd.normal({ keys, bang = true }) end) end
    local after = api.nvim_win_call(from, vim.fn.winsaveview)
    local changed = from ~= self.win and not vim.deep_equal(before, after)
    local scrolled = before.topline ~= after.topline or before.topfill ~= after.topfill or before.skipcol ~= after.skipcol
    local reading = from == self.win and (scrolled or before.lnum ~= after.lnum or before.col ~= after.col)
    -- A fitting top-pinned card must settle in this input turn, not in a
    -- later source/idle callback. Native motion into context still owns its
    -- viewport, as does prose taller than the window.
    local fitting_scroll = keys and from == self.win and scrolled and self.detail_layout
      and self.detail_layout.card_height <= vim.fn.getwininfo(self.win)[1].height
      and before.topline == self.detail_layout.first and before.skipcol == 0
      and after.lnum >= self.detail_layout.first and after.lnum <= self.detail_layout.last
    local edge_scroll = false
    if self.detail_win and from == self.win then
      local layout = self.detail_layout
      local was_reading = layout.reading
      if layout.initial and not vim.deep_equal(after, layout.initial) then layout.reading = true end
      local delta = display_distance(from, before, after)
      -- Sticky layout can remove every leading row. Ctrl-y still needs to
      -- scroll code back towards the summary, even though Markdown is at BOF.
      local source_view = self.scroll_views[self.source]
      local backward = keys and keys:match("^(%d*)\25$")
      local requested = backward and (tonumber(backward) or 1)
      if requested and after.topline == 1 and after.skipcol == 0 and requested > -delta
          and (source_view.topline > 1 or source_view.topfill > 0 or source_view.skipcol > 0) then
        delta = -requested
        edge_scroll = true
      end
      if delta ~= 0 then
        local action = api.nvim_replace_termcodes(math.abs(delta) .. (delta > 0 and "<C-e>" or "<C-y>"), true, false, true)
        api.nvim_win_call(self.source, function()
          -- Reading can select an anchored row inside scrolloff while keeping
          -- code's viewport fixed. Native scrolling would correct that margin
          -- first and lose part of the forwarded delta. Measure from the saved
          -- view, not winline()/screenpos(), whose screen cache can be stale.
          local height, row = vim.fn.getwininfo(self.source)[1].height, 0
          local column = vim.fn.virtcol(".") - 1
          if source_view.lnum >= source_view.topline and (source_view.lnum > source_view.topline or column >= source_view.skipcol) then
            row = api.nvim_win_text_height(self.source, { start_row = source_view.topline - 1,
              end_row = source_view.lnum - 1, start_vcol = source_view.skipcol, end_vcol = column + 1 }).all
              + source_view.topfill
          end
          local margin = math.min(vim.wo.scrolloff, math.floor((height - 1) / 2))
          if row <= margin or row > height - margin then
            local local_margin = api.nvim_get_option_value("scrolloff", { win = self.source, scope = "local" })
            vim.wo.scrolloff = 0
            vim.fn.winrestview(source_view)
            vim.cmd("normal! M")
            local centered = vim.fn.winsaveview()
            centered.topline, centered.topfill, centered.skipcol = source_view.topline, source_view.topfill, source_view.skipcol
            vim.fn.winrestview(centered)
            vim.wo.scrolloff = local_margin
          end
          vim.cmd.normal({ action, bang = true })
        end)
        local moved = display_distance(self.source, source_view, api.nvim_win_call(self.source, vim.fn.winsaveview))
        if fitting_scroll and moved == 0 then
          -- A native source limit is not a reading action. Undo only the
          -- speculative reader step and any source scrolloff normalization.
          api.nvim_win_call(self.source, function() vim.fn.winrestview(source_view) end)
          api.nvim_win_call(self.win, function() vim.fn.winrestview(before) end)
          layout.reading = was_reading
          reading, scrolled, fitting_scroll = false, false, false
        else
          if edge_scroll and moved ~= 0 then reading, layout.reading = true, true end
          self.overview.scrolled = true
          changed = true
          scrolled = true
        end
      end
    end
    local driver = from == self.win and self.source or from
    if changed then self:sync_sources(api.nvim_win_get_cursor(driver)[1], driver, scrolled) end
    if self.detail_win and (fitting_scroll or edge_scroll or from ~= self.win and (self.source ~= from or scrolled)) then
      if from ~= self.win and self.source ~= from then self.source, self.folds = from, {}; self:render() end
      self:place_detail()
    end
    if self.detail_win and from == self.win then
      self.projection = self:project()
      self:decorate_detail_context()
      -- Native scrolling may move code's cursor for scrolloff, or change the
      -- target under a pinned reader without moving its cursor at all. Select
      -- only after viewport/placement corrections, before caching final views.
      local layout = self.detail_layout
      local row = api.nvim_win_get_cursor(self.win)[1]
      local context = layout.rows[row]
      if reading and (context and context.active or row >= layout.first and row <= layout.last) then
        local target = self:detail_target()
        if target then self:select_source(target) end
      end
    end
    self.scroll_views = {}
    for candidate in pairs(self:windows()) do self.scroll_views[candidate] = api.nvim_win_call(candidate, vim.fn.winsaveview) end
    self.scroll_views[self.win] = api.nvim_win_call(self.win, vim.fn.winsaveview)
    self.syncing = false
    if not self.detail_win then self:sync(from) end
  end

  function pane:sync(from)
    if self.closed or self.rendering or self.syncing or not api.nvim_win_is_valid(self.source) or not api.nvim_win_is_valid(self.win) then return end
    if not self:detail_valid() then return end
    if from ~= self.win and not self:windows()[from] then return end
    if self.detail_win then
      local layout = self.detail_layout
      local context = from == self.win and layout and layout.rows[api.nvim_win_get_cursor(self.win)[1]]
      if context and context.item and not context.active then
        local target = self:detail_target()
        self:back(true)
        api.nvim_win_set_cursor(target.win, { target.line, 0 })
        self:sync_sources(target.line, target.win)
        self:sync(target.win)
      else
        self:scroll(nil, from)
      end
      return
    end
    self.syncing = true
    if from ~= self.win and from ~= self.source then
      self.source, self.folds = from, {}
      api.nvim_win_call(self.win, function() vim.cmd("silent! normal! zE") end)
      self:render()
    end
    if from == self.win then
      local view = api.nvim_win_call(self.win, vim.fn.winsaveview)
      local previous = self.scroll_views and self.scroll_views[self.win]
      local moved = previous and (view.topline ~= previous.topline or view.topfill ~= previous.topfill)
      local info = vim.fn.getwininfo(self.win)[1]
      local screen_row = vim.fn.screenpos(self.win, view.lnum, 1).row - info.winrow - info.winbar
      local line = math.min(api.nvim_win_get_cursor(self.win)[1], api.nvim_buf_line_count(api.nvim_win_get_buf(self.source)))
      local overflow = self.overflow[view.lnum]
      if overflow then line = self:locate(overflow).row end
      local cursor = api.nvim_win_get_cursor(self.source)
      if cursor[1] ~= line then
        local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(self.source), line - 1, line, false)[1] or ""
        api.nvim_win_set_cursor(self.source, { line, math.min(cursor[2], math.max(0, #text - 1)) })
      end
      if moved and not overflow then
        api.nvim_win_call(self.source, function()
          local source_view = vim.fn.winsaveview()
          source_view.skipcol = view.topline == source_view.topline and source_view.skipcol or 0
          source_view.topline, source_view.topfill = view.topline, view.topfill
          vim.fn.winrestview(source_view)
          local source_info = vim.fn.getwininfo(self.source)[1]
          local row = vim.fn.screenpos(self.source, line, vim.fn.col(".")).row
          -- The notes' logical row can represent a late wrap segment. A new
          -- logical topline alone may hide that column in a screen-filling line.
          if row == 0 then
            vim.cmd.normal({ "zz", bang = true })
            row = vim.fn.screenpos(self.source, line, vim.fn.col(".")).row
          end
          if row > 0 and screen_row >= 0 then
            local delta = row - source_info.winrow - source_info.winbar - screen_row
            if delta ~= 0 then
              vim.cmd.normal({ api.nvim_replace_termcodes(math.abs(delta) .. (delta > 0 and "<C-e>" or "<C-y>"), true, false, true), bang = true })
            end
          end
        end)
      end
    end
    self:sync_sources(api.nvim_win_get_cursor(self.source)[1])
    -- Source-driven motion never writes the source cursor/column or options.
    self:align()
    self.syncing = false
  end

  function pane:move(direction, count)
    if self.closed or self.detail_win then return end
    count = count or 1
    local row = api.nvim_win_get_cursor(self.win)[1]
    if not vim.wo[self.source].diff or self.overflow[row] or self.overflow[row + direction] then
      api.nvim_win_call(self.win, function()
        vim.cmd.normal({ count .. (direction > 0 and "j" or "k"), bang = true })
      end)
      self:sync(self.win)
      return
    end
    local source, line = self.source, api.nvim_win_get_cursor(self.win)[1]
    local coordinates = self:coordinates(source)
    -- Comparison rows are shared, but filler cannot hold a native cursor.
    -- Traverse on whichever real side owns the row, rendering only once after
    -- a counted motion. Closed folds remain a single logical navigation stop.
    for _ = 1, math.min(count, coordinates[#coordinates]) do
      local last = direction > 0 and api.nvim_win_call(source, function() return vim.fn.foldclosedend(line) end) or -1
      local coordinate = self:coordinates(source)[last >= 0 and last or line] + direction
      if coordinate < 1 then break end
      local target = self:locate(coordinate, source)
      local destination = source
      if target.offset then
        destination = nil
        for candidate in pairs(self:windows()) do
          if candidate ~= source and vim.wo[candidate].diff then
            local real = self:locate(coordinate, candidate)
            if not real.offset then destination, target = candidate, real; break end
          end
        end
      end
      if not destination then break end
      source, line = destination, target.row
      local first = api.nvim_win_call(source, function() return vim.fn.foldclosed(line) end)
      if first >= 0 then line = first end
    end
    local cursor = api.nvim_win_get_cursor(source)
    local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(source), line - 1, line, false)[1] or ""
    api.nvim_win_set_cursor(source, { line, math.min(cursor[2], math.max(0, #text - 1)) })
    self:sync(source)
    self:sync(self.win)
  end

  function pane:jump(direction, count)
    if self.closed or self.detail_win or #self.populated == 0 then return end
    local row, candidates = api.nvim_win_get_cursor(self.win)[1], {}
    -- Folded summaries are one populated presentation boundary, not multiple
    -- indistinguishable stops inside the same closed fold.
    for _, line in ipairs(self.populated) do
      local first = api.nvim_win_call(self.source, function() return vim.fn.foldclosed(line) end)
      local target = first >= 0 and first or line
      if candidates[#candidates] ~= target then candidates[#candidates + 1] = target end
    end
    local index
    if direction > 0 then
      for i, line in ipairs(candidates) do if line > row then index = i; break end end
    else
      for i = #candidates, 1, -1 do if candidates[i] < row then index = i; break end end
    end
    if not index then return end
    index = math.max(1, math.min(#candidates, index + direction * ((count or 1) - 1)))
    -- Explicit explanation jumps reveal the summary's first wrapped segment.
    local line = candidates[index]
    if self.overflow[line] then line = self:locate(self.overflow[line]).row end
    api.nvim_win_set_cursor(self.source, { line, 0 })
    api.nvim_win_set_cursor(self.win, { candidates[index], 0 })
    api.nvim_win_call(self.source, function() vim.cmd.normal({ "zz", bang = true }) end)
    self:sync(self.source)
  end

  function pane:close()
    if self.closed then return end
    self:focus(true)
    self.closed = true
    self:headers(true)
    clear_detail_marks()
    self:stop_spinner()
    vim.on_key(nil, detail_ns)
    api.nvim_del_augroup_by_id(self.group)
    local normal = {}
    if api.nvim_win_is_valid(self.win) then
      for _, candidate in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(self.win))) do
        if api.nvim_win_get_config(candidate).relative == "" then normal[#normal + 1] = candidate end
      end
    end
    if #normal == 1 and normal[1] == self.win then
      api.nvim_win_call(self.win, function() vim.cmd("new") end)
    end
    for _, owned in ipairs({ self.detail_win or -1, self.win }) do
      if api.nvim_win_is_valid(owned) then api.nvim_win_close(owned, true) end
    end
    for _, owned in ipairs({ self.buf, self.detail_buf or -1 }) do
      if api.nvim_buf_is_valid(owned) then api.nvim_buf_delete(owned, { force = true }) end
    end
    if on_close then on_close() end
  end

  if keymaps then keymaps(buf) end
  vim.keymap.set("n", "<CR>", function() pane:detail() end, { buffer = buf })
  vim.keymap.set("n", "K", function() pane:detail() end, { buffer = buf })
  vim.keymap.set("n", "j", function() pane:move(1, vim.v.count1) end, { buffer = buf })
  vim.keymap.set("n", "k", function() pane:move(-1, vim.v.count1) end, { buffer = buf })
  vim.keymap.set("n", "n", function() pane:jump(1, vim.v.count1) end, { buffer = buf })
  vim.keymap.set("n", "p", function() pane:jump(-1, vim.v.count1) end, { buffer = buf })
  vim.keymap.set("n", "N", function() pane:jump(-1, vim.v.count1) end, { buffer = buf })
  vim.keymap.set("n", "q", function() pane:close() end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() pane:close() end, { buffer = buf })
  for _, key in ipairs({ "<C-f>", "<C-b>", "<C-d>", "<C-u>", "<C-e>", "<C-y>", "<ScrollWheelDown>", "<ScrollWheelUp>" }) do
    local action = key == "<ScrollWheelDown>" and "3<C-e>" or key == "<ScrollWheelUp>" and "3<C-y>" or key
    local keys = vim.api.nvim_replace_termcodes(action, true, false, true)
    vim.keymap.set("n", key, function()
      local count = not key:find("ScrollWheel", 1, true) and vim.v.count > 0 and vim.v.count or ""
      pane:scroll(count .. keys)
    end, { buffer = buf })
  end
  local pending = false
  local rebuild = false
  local function schedule(full)
    rebuild = rebuild or full == true
    if pending or pane.closed or pane.rendering or pane.syncing or pane.detail_win and not full then return end
    pending = true
    local generation = pane.display_generation
    vim.schedule(function()
      pending = false
      if pane.closed then return end
      -- WinClosed cleanup is also deferred. A geometry callback queued first
      -- can run after Diffview has destroyed its windows but before cleanup.
      if not api.nvim_win_is_valid(pane.win) or not api.nvim_win_is_valid(pane.source) then pane:close(); return end
      if not pane:detail_valid() then return end
      if generation ~= pane.display_generation then
        if rebuild then schedule(true) end
        return
      end
      local render = rebuild
      rebuild = false
      local current_win = api.nvim_get_current_win()
      if pane.detail_win then
        if pane:windows()[current_win] and pane.source ~= current_win then pane.source, pane.folds = current_win, {} end
        pane:render()
        local ranges = {}
        for _, id in ipairs(pane.detail_layout.ids) do
          vim.list_extend(ranges, pane:ranges(pane.result.notes[id].anchors, pane.snapshot.windows))
        end
        pane.detail_layout.ranges = ranges
        pane:place_detail()
      elseif render then pane:render()
      elseif current_win == pane.win or pane:windows()[current_win] then pane:sync(current_win)
      else pane:align() end
    end)
  end
  api.nvim_create_autocmd("WinScrolled", { group = pane.group, callback = function(event)
    if pane.syncing or pane.rendering then return end
    local current_win = api.nvim_get_current_win()
    local scrolled = tonumber(event.match)
    if pane:windows()[current_win] then pane:scroll(nil, current_win)
    elseif scrolled and pane:windows()[scrolled]
        and (current_win ~= pane.win or pane.wheel_input and vim.fn.getmousepos().winid == scrolled) then pane:scroll(nil, scrolled)
    elseif current_win == pane.win then pane:sync(pane.win)
    else schedule() end
  end })
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "ModeChanged" }, { group = pane.group, callback = function() schedule() end })
  api.nvim_create_autocmd("WinLeave", { group = pane.group, callback = function()
    if api.nvim_get_current_win() == pane.win then pane:focus(true) end
  end })
  api.nvim_create_autocmd("WinResized", { group = pane.group, callback = function() schedule(true) end })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, { group = pane.group, callback = function()
    local current_win = api.nvim_get_current_win()
    if current_win == pane.win or pane:windows()[current_win] then pane:sync(current_win) end
  end })
  -- zc/zo can change folds without moving the cursor or topline, and have no
  -- dedicated event. Check only viewport geometry when the editor becomes idle.
  api.nvim_create_autocmd("SafeState", { group = pane.group, callback = function()
    if pane.closed or pane.rendering or pane.syncing or not api.nvim_win_is_valid(pane.source) then return end
    if not pane:detail_valid() then return end
    if pane.detail_folds_dirty then
      pane.detail_folds_dirty = nil
      if pane.detail_win then schedule(true); return end
    end
    pane:detail_reflow()
    local current_win = api.nvim_get_current_win()
    if current_win == pane.win or pane:windows()[current_win] then
      local before = pane.scroll_views and pane.scroll_views[current_win]
      if not vim.deep_equal(before, api.nvim_win_call(current_win, vim.fn.winsaveview)) then pane:sync(current_win) end
    end
    local source = pane:windows()[current_win] and current_win or pane.source
    local projection = source == pane.source and pane:project() or M.project(source)
    if source ~= pane.source or not vim.deep_equal(projection, pane.projection) then
      if pane.detail_win then schedule(true) else pane:sync(source) end
    end
  end })
  api.nvim_create_autocmd("CmdlineLeave", { group = pane.group, pattern = ":", callback = function()
    if pane.detail_win and pane:windows()[api.nvim_get_current_win()] then
      local command = vim.fn.getcmdline()
      if command:find("fold", 1, true) or command:match("norm.*z[cCoOaAMRrmxXEfFdDv]") then pane.detail_folds_dirty = true end
    end
  end })
  api.nvim_create_autocmd("OptionSet", { group = pane.group, pattern = { "wrap", "foldenable", "foldmethod", "foldlevel",
    "foldminlines", "winbar", "number", "relativenumber", "signcolumn", "foldcolumn", "linebreak", "breakindent", "showbreak",
    "cursorline", "cursorlineopt" },
    callback = function(event)
      if pane.closed or pane.updating_state or pane.syncing or pane.rendering then return end
      if event.match == "winbar" then pane:headers() end
      schedule(pane.detail_win ~= nil)
    end })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "DiffUpdated" }, { group = pane.group, callback = function(event)
    if pane.closed or not api.nvim_win_is_valid(pane.source) then return end
    local affected = event.event == "DiffUpdated"
    for candidate in pairs(pane:windows()) do
      if event.buf == api.nvim_win_get_buf(candidate) then affected = true end
    end
    if affected then
      pane.comparison = nil
      schedule(true)
    end
  end })
  api.nvim_create_autocmd("WinClosed", { group = pane.group, callback = function(event)
    if pane:windows()[tonumber(event.match)] or tonumber(event.match) == pane.win then
      pane:stop_spinner()
      -- Closing another split inside WinClosed can abort Neovim's layout change.
      vim.schedule(function() pane:close() end)
    end
  end })
  pane:render()
  return pane
end

return M
