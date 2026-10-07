"""Capture the actual Neovim screen grid, not a generated design mockup.

Run with a Python environment containing pynvim and Pillow. No user config is
loaded. Output belongs under .amp/in/artifacts (locally excluded from Git).
"""
from pathlib import Path
import argparse
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


parser = argparse.ArgumentParser()
parser.add_argument("--output", default=".amp/in/artifacts")
parser.add_argument("--nvim", default="nvim")
parser.add_argument("--font", default="/System/Library/Fonts/Menlo.ttc")
parser.add_argument("--runtime", action="append", default=[], help="Optional plugin/parser runtime directory (repeatable)")
parser.add_argument("--frame", type=int, help="Freeze the loader at this animation frame for repeatable captures")
parser.add_argument("--animate", action="store_true", help="Capture live redraws as a looping GIF")
parser.add_argument("--states", nargs="+", default=["code", "detail", "folded", "wrapped", "narrow", "pending",
                                                    "failed", "stale", "cancelled", "global-statusline",
                                                    "diff", "diff-detail", "diff-scroll", "diff-switch", "diff-stale", "diff-failed"])
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(args.font, 16)
for state in args.states:
    nvim = pynvim.attach("child", argv=[args.nvim, "--embed", "-u", "NONE", "-n"])
    width, height = (220 if state.startswith("diff") else 72 if state in ("narrow", "detail-narrow", "overlap-narrow") else 140), 28
    screen = Screen(width, height)
    nvim.ui_attach(width, height, rgb=True, ext_linegrid=True)
    nvim.vars["capture_runtime"] = args.runtime
    nvim.vars["capture_state"] = state
    chooser = state == "range-chooser"
    # Native vim.ui.select blocks in inputlist; consume its live redraws before
    # sending cancellation rather than waiting for the fixture RPC to finish.
    nvim.command("luafile tests/visual.lua", async_=chooser)
    if args.frame is not None:
        nvim.exec_lua("capture_pane:stop_spinner(); capture_pane.frame = ...; capture_pane:state()", args.frame)
    frames = []
    if chooser:
        while not any("Expand explanation:" in "".join(cell[0] for cell in row) for row in screen.cells):
            message = nvim.next_message()
            if message.type == "notification" and message.name == "redraw":
                screen.redraw(message.args)
        frames.append(screen.draw(font))
        nvim.input("0\r")
    else:
        for _ in range(48 if args.animate else 1):
            nvim.exec_lua("""
          local channel, delay = ...
          vim.wait(delay)
          vim.cmd('redraw!')
          vim.schedule(function()
            vim.rpcnotify(channel, 'capture_done')
          end)
        """, nvim.channel_id, 100 if args.animate else 250)
            while True:
                message = nvim.next_message()
                if message.type == "notification" and message.name == "capture_done":
                    break
                if message.type == "notification" and message.name == "redraw":
                    screen.redraw(message.args)
            frames.append(screen.draw(font))
    if state.startswith("boundary-"):
        # Inspect every published frame, including those before SafeState's
        # deferred reconciliation. A final screenshot cannot detect a bounce.
        frames[0].save(out / f"explainr-{state}-before.png")
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
                            frames[-1].save(out / f"explainr-{state}-frame-{len(frames) - 1}.png")
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
    path = out / f"explainr-{state}.{'gif' if args.animate else 'png'}"
    if args.animate:
        # A shared palette avoids introducing color flicker in unchanged text.
        palette = frames[0].convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
        frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=100, loop=0)
    else:
        frames[0].save(path)
    print(path)
    nvim.exec_lua("if _G.capture_review then _G.capture_review:close() end")
    try:
        nvim.command("qa!")
    except EOFError:
        pass
