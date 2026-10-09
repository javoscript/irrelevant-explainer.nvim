"""Capture the actual Neovim screen grid, not a generated design mockup.

Run with a Python environment containing pynvim and Pillow. Default: -u NONE.
Opt in locally: python tests/render.py --personal-config ~/.config/nvim --demo
  --output .amp/in/artifacts/publication-media
This loads the real init with a process-local styling-only Lazy spec selection;
installed theme/statusline/gutters/parsers are retained, services are not started.
Never run this mode against private buffers. Output is review evidence, not an
automatic approval to publish: inspect PNGs, every trace/GIF frame, and metadata.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import tempfile
import pynvim
from PIL import Image, ImageDraw, ImageFont


class Screen:
    """Attributes come from Neovim's RGB UI protocol, not a guessed palette."""

    def __init__(self, width, height):
        self.cells = [[(" ", 0) for _ in range(width)] for _ in range(height)]
        self.attrs = {0: {}}
        self.fg, self.bg, self.sp = 0xFFFFFF, 0x000000, 0xFFFFFF

    def redraw(self, events):
        for event, *updates in events:
            for update in updates:
                if event == "default_colors_set":
                    self.fg, self.bg, self.sp = update[:3]
                elif event == "hl_attr_define":
                    self.attrs[update[0]] = update[1]
                elif event == "grid_resize" and update[0] == 1:
                    _, width, height = update
                    self.cells = [[(" ", 0) for _ in range(width)] for _ in range(height)]
                elif event == "grid_clear" and update[0] == 1:
                    self.cells = [[(" ", 0) for _ in row] for row in self.cells]
                elif event == "grid_line" and update[0] == 1:
                    _, row, col, cells, *_ = update
                    attr = 0
                    for cell in cells:
                        char = cell[0]
                        if len(cell) > 1:
                            attr = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            self.cells[row][col] = (char, attr)
                            col += 1
                elif event == "grid_scroll" and update[0] == 1:
                    _, top, bottom, left, right, rows, cols = update
                    previous = [row[:] for row in self.cells]
                    for y in range(top, bottom):
                        for x in range(left, right):
                            src_y, src_x = y + rows, x + cols
                            self.cells[y][x] = (previous[src_y][src_x]
                                                if top <= src_y < bottom and left <= src_x < right else (" ", 0))

    def draw(self, font):
        width, height = len(self.cells[0]), len(self.cells)
        image = Image.new("RGB", (width * 10 + 32, height * 23 + 32), self.rgb(self.bg))
        draw = ImageDraw.Draw(image)
        # Paint all cell backgrounds first so a wide glyph's continuation cell
        # never erases the right half of the glyph.
        for y, row in enumerate(self.cells):
            for x, (_, attr_id) in enumerate(row):
                attr = self.attrs[attr_id]
                fg, bg = attr.get("foreground", self.fg), attr.get("background", self.bg)
                if attr.get("reverse"):
                    fg, bg = bg, fg
                px, py = 16 + x * 10, 16 + y * 23
                draw.rectangle((px, py, px + 9, py + 22), fill=self.rgb(bg))
        for y, row in enumerate(self.cells):
            for x, (char, attr_id) in enumerate(row):
                attr = self.attrs[attr_id]
                fg = attr.get("background", self.bg) if attr.get("reverse") else attr.get("foreground", self.fg)
                px, py = 16 + x * 10, 16 + y * 23
                if char:
                    draw.text((px, py), char, font=font, fill=self.rgb(fg),
                              stroke_width=1 if attr.get("bold") else 0)
                if any(attr.get(key) for key in ("underline", "undercurl", "underdouble", "underdotted", "underdashed")):
                    draw.line((px, py + 21, px + 9, py + 21), fill=self.rgb(attr.get("special", self.sp)))
                if attr.get("strikethrough"):
                    draw.line((px, py + 12, px + 9, py + 12), fill=self.rgb(fg))
        return image

    @staticmethod
    def rgb(value):
        return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


PERSONAL_STARTUP = r"""
local config, installed = ...
vim.g.capture_personal = true
vim.o.loadplugins = true -- -u NONE disabled it before the opt-in real init
vim.opt.runtimepath:prepend(config)
vim.opt.runtimepath:append(installed .. '/site')
vim.opt.runtimepath:prepend(installed .. '/lazy/lazy.nvim')
for _, provider in ipairs({'python3', 'node', 'ruby', 'perl'}) do
  vim.g['loaded_' .. provider .. '_provider'] = 0
end
vim.o.shada, vim.o.shadafile = '', 'NONE'
vim.o.swapfile, vim.o.backup, vim.o.writebackup, vim.o.undofile = false, false, false, false
-- The real lazy-bootstrap executes, but only reviewed styling specs are handed
-- to Lazy. No import of private/provider/session/dashboard plugin specs occurs.
local lazy = require('lazy')
local setup = lazy.setup
lazy.setup = function(_, opts)
  local trees = require('plugins.treesitter')[1]
  trees.dependencies, trees.build = {}, nil -- no parser manager / TSUpdate
  local specs = {require('plugins.themes')[1], require('plugins.lualine'),
    require('plugins.snacks')[1], require('plugins.incline'), trees}
  for _, spec in ipairs(require('plugins')) do
    if type(spec) == 'table' and spec[1] == 'akinsho/bufferline.nvim' then
      specs[#specs + 1] = spec
    end
  end
  local snacks = specs[3]
  for _, name in ipairs({'dashboard', 'picker', 'scratch', 'terminal', 'notifier', 'image'}) do
    snacks.opts[name] = {enabled = false}
  end
  opts.root = installed .. '/lazy'
  opts.lockfile = vim.fn.stdpath('state') .. '/capture-lock.json'
  opts.install = {missing = false}
  opts.checker = {enabled = false}
  opts.change_detection = {enabled = false, notify = false}
  opts.pkg = {enabled = false}
  opts.readme = {enabled = false}
  opts.performance = {rtp = {reset = false}}
  setup(specs, opts)
  vim.g.capture_lazy_bootstrap = true
end
-- Refuse processes except Git fixture operations and the exact offline agent.
local function allowed(cmd)
  assert(type(cmd) == 'table', 'capture refuses shell commands')
  local exe = vim.fn.fnamemodify(cmd[1], ':t')
  assert(exe == 'git' or (exe == 'python3' and cmd[2] == vim.g.capture_checkout .. '/tests/fixtures/agent.py'),
    'capture refuses non-fixture process')
  if exe == 'git' then
    for _, arg in ipairs(cmd) do
      assert(not vim.tbl_contains({'clone', 'fetch', 'pull', 'push', 'ls-remote'}, arg), 'capture refuses Git network')
    end
  end
end
local system, fn_system, jobstart, spawn = vim.system, vim.fn.system, vim.fn.jobstart, vim.uv.spawn
vim.system = function(cmd, ...) allowed(cmd); return system(cmd, ...) end
vim.fn.system = function(cmd, ...) allowed(cmd); return fn_system(cmd, ...) end
vim.fn.jobstart = function(cmd, ...) allowed(cmd); return jobstart(cmd, ...) end
vim.uv.spawn = function(cmd, opts, ...)
  allowed(vim.list_extend({cmd}, opts.args or {})); return spawn(cmd, opts, ...)
end
-- No private notification chrome. Unexpected errors still fail the RPC/check.
vim.notify = function() end
dofile(config .. '/init.lua')
lazy.setup = setup
vim.o.shada, vim.o.shadafile = '', 'NONE'
vim.o.swapfile, vim.o.backup, vim.o.writebackup, vim.o.undofile = false, false, false, false
vim.opt.clipboard = ''
vim.g.clipboard = nil
lazy.load({plugins = {'incline.nvim', 'bufferline.nvim', 'lualine.nvim'}})
-- The floating filename widget covers the first source line in split captures.
-- Hide only that overlay in this disposable process, not the personal config.
require('incline').disable()
vim.wait(300)
vim.opt.clipboard = '' -- options.lua's scheduled clipboard setup has now run
vim.g.clipboard = nil
assert(vim.g.capture_lazy_bootstrap and package.loaded.options and package.loaded.keymaps
  and package.loaded.autocommands and package.loaded.diagnostic, 'real init did not load')
assert(vim.g.colors_name == 'rose-pine' and package.loaded.lualine, 'personal styling missing')
assert(not package.loaded.explainr and not package.loaded.opencode, 'personal agent/plugin loaded')
"""


def fingerprints(roots):
    """Compare personal config/state/results without recording their contents."""
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for root in roots if root.exists() for path in root.rglob('*') if path.is_file()}


parser = argparse.ArgumentParser()
parser.add_argument("--output", default=".amp/in/artifacts")
parser.add_argument("--nvim", default="nvim")
parser.add_argument("--font", default="/System/Library/Fonts/Menlo.ttc")
parser.add_argument("--personal-config", type=Path, help="Opt-in real config directory (local-only)")
parser.add_argument("--personal-data", type=Path, default=Path.home() / ".local/share/nvim",
                    help="Installed read-only plugin/parser directory")
parser.add_argument("--demo", action="store_true", help="Four publication captures with asserted real interactions")
parser.add_argument("--runtime", action="append", default=[], help="Optional plugin/parser runtime directory (repeatable)")
parser.add_argument("--frame", type=int, help="Freeze the loader at this animation frame for repeatable captures")
parser.add_argument("--animate", action="store_true", help="Capture live redraws as a looping GIF")
parser.add_argument("--states", nargs="+", default=["code", "detail", "folded", "wrapped", "narrow", "pending",
                                                    "failed", "stale", "cancelled", "global-statusline",
                                                    "diff", "diff-detail", "diff-scroll", "diff-switch", "diff-stale", "diff-failed"])
args = parser.parse_args()
checkout = Path(__file__).resolve().parent.parent
out = Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(args.font, 16)
if args.demo:
    args.states = ["publication-code", "publication-code-motion", "diff-file-overview", "diff-publication-review"]
personal_roots = [args.personal_config] if args.personal_config else []
personal_roots += [Path.home() / ".local/state/nvim", Path.home() / ".cache/nvim/explainr"]
before = fingerprints(personal_roots) if args.personal_config else {}
# Every writable Neovim standard directory belongs to this disposable process.
cache_root = tempfile.TemporaryDirectory(prefix="irrelevant-explainer-capture-")
workspace = Path(cache_root.name).resolve()
for directory in ("cache", "state", "data", "config"):
    os.environ[f"XDG_{directory.upper()}_HOME"] = str(workspace / directory)
(workspace / "data/nvim/lazy").mkdir(parents=True)
if args.personal_config:
    assert (args.personal_data / "lazy/lazy.nvim/lua/lazy/init.lua").is_file()
    (workspace / "data/nvim/lazy/lazy.nvim").symlink_to(args.personal_data / "lazy/lazy.nvim")
os.environ["GIT_CONFIG_GLOBAL"] = os.devnull
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
for name, default in (("DIFFVIEW", "diffview.nvim"), ("PLENARY", "plenary.nvim")):
    os.environ.setdefault(f"IRRELEVANT_EXPLAINER_{name}_PATH", str(args.personal_data / "lazy" / default))
evidence = []
for state in args.states:
    nvim = pynvim.attach("child", argv=[args.nvim, "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    width, height = (240 if state.startswith("diff") and args.demo else 220 if state.startswith("diff")
                     else 72 if state in ("narrow", "detail-narrow", "overlap-narrow") else 140), 28
    if state.startswith("publication-code"):
        width = 160
    screen = Screen(width, height)
    nvim.ui_attach(width, height, rgb=True, ext_linegrid=True)
    nvim.vars["capture_checkout"] = str(checkout)
    local_workspace = workspace / state
    local_workspace.mkdir()
    nvim.vars["capture_workspace"] = str(local_workspace)
    if args.personal_config:
        nvim.command("lcd " + nvim.funcs.fnameescape(str(local_workspace)))
        nvim.exec_lua(PERSONAL_STARTUP, str(args.personal_config.resolve()), str(args.personal_data.resolve()))
    nvim.vars["capture_runtime"] = args.runtime
    nvim.vars["capture_state"] = state
    nvim.vars["capture_demo"] = args.demo
    chooser = state == "range-chooser"
    # Native vim.ui.select blocks in inputlist; consume its live redraws before
    # sending cancellation rather than waiting for the fixture RPC to finish.
    nvim.command("luafile " + nvim.funcs.fnameescape(str(checkout / "tests/visual.lua")), async_=chooser)
    if args.frame is not None:
        nvim.exec_lua("capture_pane:stop_spinner(); capture_pane.frame = ...; capture_pane:state()", args.frame)
    frames = []
    trace = []
    trace_hashes = set()
    images = {}
    actions = []

    def remember():
        text = '\n'.join(''.join(cell[0] for cell in row) for row in screen.cells)
        # Fail closed, not image redaction: these paths must never enter media.
        assert not any(value in text for value in ('/Users/', '/home/', '.config/nvim', 'Development/', 'opencode.json')), 'private chrome in capture'
        digest = hashlib.sha256(repr((screen.cells, screen.attrs, screen.fg, screen.bg, screen.sp)).encode()).hexdigest()
        if digest not in trace_hashes:
            trace_hashes.add(digest)
            image = screen.draw(font)
            images[digest] = image
            trace.append(image)
        return images[digest]

    def settle(delay=250):
        nvim.exec_lua("""
          local channel, delay = ...
          vim.wait(delay)
          vim.cmd('redraw!')
          vim.schedule(function() vim.rpcnotify(channel, 'capture_done') end)
        """, nvim.channel_id, delay)
        while True:
            message = nvim.next_message()
            if message.type == "notification" and message.name == "capture_done":
                break
            if message.type == "notification" and message.name == "redraw":
                for event in message.args:
                    screen.redraw([event])
                    if event[0] == 'flush':
                        remember()
        return remember()

    def check(lua):
        nvim.exec_lua("local p, api = capture_pane, vim.api; " + lua)

    def interact(keys, assertion):
        start = len(trace)
        print(f"{state}: input {keys!r}", flush=True)
        nvim.exec_lua("vim.api.nvim_feedkeys(..., 'xt', false)", keys)
        image = settle()
        check(assertion)
        actions.append({"keys": repr(keys), "assertion": assertion})
        # Include every distinct flushed input frame, not just endpoints.
        frames.extend(trace[start:])
        frames.append(image)

    if chooser:
        while not any("Expand explanation:" in "".join(cell[0] for cell in row) for row in screen.cells):
            message = nvim.next_message()
            if message.type == "notification" and message.name == "redraw":
                screen.redraw(message.args)
        frames.append(screen.draw(font))
        nvim.input("0\r")
    else:
        for _ in range(48 if args.animate else 1):
            frames.append(settle(100 if args.animate else 250))
    if args.demo and state == "publication-code-motion":
        check("assert(not p.detail_buf and api.nvim_win_get_cursor(p.source)[1] == 4)")
        interact("\r", "assert(p.detail_index == 2 and p.detail_buf and api.nvim_get_current_win() == p.win)")
        interact("3j", "assert(p.detail_index == 2 and api.nvim_win_get_cursor(p.source)[1] > 4)")
        check("capture_top = api.nvim_win_call(p.source, vim.fn.winsaveview).topline")
        interact("\x05", "assert(p.detail_buf and api.nvim_win_call(p.source, vim.fn.winsaveview).topline > capture_top)")
        check("capture_line = api.nvim_win_get_cursor(p.source)[1]")
        interact("\r", "assert(not p.detail_buf and api.nvim_win_get_cursor(p.source)[1] == capture_line and api.nvim_win_get_cursor(p.win)[1] == capture_line)")
        interact("n", "assert(api.nvim_win_get_cursor(p.source)[1] == 16 and api.nvim_win_get_cursor(p.win)[1] == 16)")
        interact("\r", "assert(p.detail_index == 3 and p.detail_buf)")
        interact("\r", "assert(not p.detail_buf and api.nvim_win_get_cursor(p.source)[1] == 16)")
    if args.demo and state == "diff-publication-review":
        check("assert(p.review_mode and capture_reference_row)")
        interact("\r", "assert(not p.review_mode and p.result); assert(require('irrelevant_explainer.diffview').current(p.source).selected.path == 'openspec/spec.md')")
        # Retained file annotations open without another fake agent invocation.
        interact("\r", "assert(p.detail_buf)")
        interact("\r", "assert(not p.detail_buf)")
        nvim.command("IrrelevantExplainerReview")
        frames.append(settle())
        check("assert(vim.wait(5000, function() return p.review_status == 'Ready · restored' end), p.review_status)")
        frames.append(settle())
        check("assert(p.review_mode and vim.deep_equal(capture_review_view, api.nvim_win_call(p.win, vim.fn.winsaveview)))")
        actions.append({"command": "IrrelevantExplainerReview", "assertion": "Review and saved reading view restored without inference"})
    if state.startswith("boundary-"):
        # Inspect every published frame, including those before SafeState's
        # deferred reconciliation. A final screenshot cannot detect a bounce.
        frames[0].save(out / f"irrelevant-explainer-{state}-before.png")
        invalid_frames = []
        for step in range(3 if state == "boundary-top" else 1):
            nvim.input("\x05" if state == "boundary-top" else "\x19")
            nvim.exec_lua("""
              local channel = ...
              vim.defer_fn(function() vim.rpcnotify(channel, 'boundary_done') end, 100)
            """, nvim.channel_id)
            while True:
                message = nvim.next_message()
                if message.type == "notification" and message.name == "boundary_done":
                    break
                if message.type == "notification" and message.name == "redraw":
                    for event in message.args:
                        screen.redraw([event])
                        if event[0] == "flush":
                            frames.append(screen.draw(font))
                            frames[-1].save(out / f"irrelevant-explainer-{state}-frame-{len(frames) - 1}.png")
                            if state == "boundary-top" and not any(
                                "Boundary explanation" in "".join(cell[0] for cell in row)
                                for row in screen.cells[1:2]
                            ):
                                invalid_frames.append(len(frames) - 1)
        if state == "boundary-top":
            assert not invalid_frames, f"Displaced card in flushed frames: {invalid_frames}"
            assert nvim.exec_lua("return vim.api.nvim_win_call(capture_pane.source, vim.fn.winsaveview).topline") == 73
        else:
            assert nvim.exec_lua("return capture_pane.detail_buf == nil"), "Ctrl-y did not escape"
            assert nvim.exec_lua("return vim.api.nvim_win_get_cursor(capture_pane.source)[1]") == 39
        print(f"{state}: checked {len(frames) - 1} input frames")
        frames = [frames[-1]]
    animated = args.animate or args.demo and state in ("publication-code-motion", "diff-publication-review")
    names = {"publication-code": "code-overview", "publication-code-motion": "code-detail",
             "diff-file-overview": "diff-overview", "diff-publication-review": "review-navigation"}
    name = names[state] if args.demo else f"irrelevant-explainer-{state}"
    path = out / f"{name}.{'gif' if animated else 'png'}"
    if animated:
        # A shared palette avoids introducing color flicker in unchanged text.
        palette = frames[0].convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
        frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=800 if args.demo else 100, loop=0)
    else:
        frames[0].save(path)
    print(path, flush=True)
    trace_dir = out / f"{name}-trace"
    trace_dir.mkdir(exist_ok=True)
    for index, image in enumerate(trace):
        image.save(trace_dir / f"{index:03d}.png")
    proof = nvim.exec_lua("""
      local p = capture_pane
      assert(vim.bo[vim.api.nvim_win_get_buf(p.win)].filetype == 'irrelevant_explainer')
      assert(vim.v.errmsg == '', vim.v.errmsg)
      local evaluated = vim.api.nvim_eval_statusline(vim.wo[p.win].winbar,
        {winid = p.win, use_winbar = true, maxwidth = vim.api.nvim_win_get_width(p.win)})
      assert(evaluated.width <= vim.api.nvim_win_get_width(p.win), 'header overflow')
      return {colorscheme = vim.g.colors_name, personal_init = vim.g.capture_lazy_bootstrap == true,
        statusline = package.loaded.lualine ~= nil, parsers = #vim.api.nvim_get_runtime_file('parser/lua.*', false) > 0,
        old_package_loaded = package.loaded.explainr ~= nil, shada_disabled = vim.o.shadafile == 'NONE',
        swap_disabled = not vim.o.swapfile,
        checkout_loaded = debug.getinfo(require('irrelevant_explainer.ui').open).source == '@' .. vim.g.capture_checkout .. '/lua/irrelevant_explainer/ui.lua',
        header = evaluated.str, header_width = evaluated.width, pane_width = vim.api.nvim_win_get_width(p.win)}
    """)
    evidence.append({"state": state, "trace_frames": len(trace), "proof": proof, "actions": actions})
    nvim.exec_lua("if _G.capture_review then _G.capture_review:close() end")
    try:
        nvim.command("qa!")
    except EOFError:
        pass
if args.personal_config:
    assert fingerprints(personal_roots) == before, 'personal config/state/results changed during capture'
(out / "capture-evidence.json").write_text(json.dumps({"states": evidence,
    "personal_files_unchanged": bool(args.personal_config), "personal_files_checked": len(before)}, indent=2))
cache_root.cleanup()
