# explainr.nvim

AI explanations alongside code and code diffs, with concise row-aligned notes and
in-pane Markdown detail. Requires **Neovim 0.11+**. Diffview is optional for code mode;
structural scopes require installed Tree-sitter parsers.

For local development with lazy.nvim:

```lua
{ dir = "/path/to/explainr.nvim", opts = {
  ai = { command = { "codex", "exec", "-", "--json", "--sandbox", "read-only" }, output = "codex" },
} }
```

Configure an already installed/authenticated external tool:

```lua
require("explainr").setup({
  ai = {
    command = { "opencode", "run", "--agent", "explain", "--format", "json" },
    output = "opencode",
    timeout_ms = 300000,
  },
  context = { max_bytes = 262144, diff = "auto", radius = 20 },
  diff = { auto_explain = false }, -- Opt in to explaining newly visited Diffview files.
})
```

The `explain` agent is user-created and should deny edits and unnecessary tools.
Explainr does not manage credentials, guarantee subscription billing, or sandbox
arbitrary commands. Provider permissions, billing, and retained history belong to
the configured tool.

## Usage

```vim
:ExplainrCode file
:ExplainrCode function
:ExplainrCode class
:'<,'>ExplainrCode selection
:ExplainrDiff file
:ExplainrDiff hunk
:ExplainrRefresh
:ExplainrCancel
:ExplainrClose
```

Code mode uses current unsaved buffer text; structural scopes support Lua
functions and Python/JavaScript/TypeScript functions/classes. File and visual
scopes need no parser. Diff mode follows a loaded two-way Diffview source and
defaults to the **whole selected coherent comparison** when it fits. Oversized
reviews automatically use the selected hunk with nearby old/new lines (or the
complete selected file for file scope), prioritizing affordable changed OpenSpec,
ADR, decision and requirements documents. Reduced coverage is visibly labeled;
the model may not cite omitted lines. Only the selected file/hunk gets notes.
File-scope explanations prioritize that file's changed hunks, with additional
notes on unchanged sections when they explain a change's effects or rationale.
Both file scopes also request a short file-purpose overview at the top. Diff
overviews include the overall purpose of the selected file's changes. The overview
references the whole file (both available diff versions), so focusing it highlights
all its content. No overview is requested for function, class, selection or hunk
scopes, or when no valid target text exists.
Staged and working comparisons are kept separate.

`context.diff` can be `"auto"` (default), `"focused"` (always reduce coverage), or
`"review"` (require the whole comparison or fail). `context.radius` controls
nearby lines in focused hunk requests; it shrinks as needed to fit the budget.
Changed decision documents are prioritized by path, not semantic relevance.
Unchanged documents are not automatically explored.

The pane opens at the far right, outside both diff sources. Colored `D` / `~` /
`?` accents distinguish documented, inferred and unknown intent. Original-side
line references and continuation rails identify each note's range. Diff summaries
sit beside the first changed line within their anchor, rather than an unchanged
block header; notes on entirely unchanged ranges stay at the range's start.
Overlapping summaries use separate available rows within their anchor ranges,
each with its own range label. Collisions prioritize narrower ranges, then
documented → inferred → unknown intent, then original result order. Other notes'
primary positions are reserved; file overviews take precedence at the file start.
When a range has no spare rows, entries use free annotation rows below it, adding
blank rows at EOF if needed. Each remains independently selectable, with its
original range label and source cursor target; source text/geometry is unchanged.
Navigation follows their displayed order. Closed folds still combine notes;
expand to read their details. The status header includes `D documented · ~ inferred · ? unknown`.
It also shows the explanation count, or your position (e.g. `2 / 5`) when
focusing/navigating an entry, in both overview and expanded detail. Folded groups
show a range such as `1–3 / 5`.
The status header sits above content from the moment the pane opens, including
initial loading, and stays there across results, refreshes, and expanded detail.
Source windows without a winbar temporarily get a matching blank header to keep
content rows aligned. These placeholders are restored when a source leaves the
pane's ownership or the pane closes; existing headers and user edits are preserved.
`Explainr` uses the theme's information accent (`ExplainrTitle`); other header
text is muted (`ExplainrMetadata`) regardless of request state. Legend symbols
use the same `ExplainrDocumented`, `ExplainrInferred`, and `ExplainrUnknown` colors
as explanation items. Narrow headers prioritize counts and abbreviate other text,
omitting the title when necessary. Themes can override these highlight groups.
In the explainer pane, focusing a collapsed summary applies the same dimming and
theme-derived tint as expanded detail: its full anchor ranges stay emphasized in both
the explainer and source buffers. Moving to a blank row or a different window
clears collapsed focus. Expand/collapse keeps focus on the same explanation.
The full anchor range is retained for references and expanded detail. **n/p** jump
to the next/previous explanation, including off-screen notes, with counts,
stopping at the first/last explanation without wrapping. Successful jumps center
the destination like **zz** in both overview and expanded detail.
**N** (**Shift+n**) also goes to the previous explanation, just like **p**.
Native cursor and viewport actions, including **zz/zt/zb**, searches,
marks, screen motions and counted scrolling, synchronize the overview and source
in both directions without remapping those actions. **K** or **Enter** expands
detail beneath the selected summary, retaining its visible position when space
allows, range/intent styling and dimmed overview context above and below it.
Following notes keep their aligned rows when space allows; a longer card puts
them below its body instead of hiding them. A fixed gutter with one padding
space prevents horizontal shifts on expansion/collapse.
Surrounding context is strongly dimmed and the expanded
body has a subtle neutral surface tint from the active colorscheme's `CursorLine`
background, softened toward `Normal`. Themes without that background use
`NormalFloat` or a faint blend of the normal text color. The gutter and left
padding stay on the dimmed backdrop, outside the tinted content.
The summary, range label, metadata
and wrapped prose margins share that background; Markdown code blocks keep
their distinct formatting. A continuous `▎`
gutter rail covers the expanded explanation, including wrapped lines, connecting
it visually to the referenced source ranges. The rail and tint extend through
the visible anchored range even past neighboring summaries, whose text stays
dimmed. A whole-file overview therefore covers the whole visible file extent.
Near the bottom, the card lifts enough to show the
first explanation line without moving code. The referenced code is temporarily
marked with a muted gutter rail; text outside the anchors is dimmed in the source
buffers (both sides in diff mode). Anchored syntax colors, Git diff backgrounds
and existing signs stay intact. Native diff foregrounds take precedence over
dimming, so changed text can remain brighter outside the anchors.
Focus follows **n/p** and stays on the summary after collapse; it clears on a
blank row, departure from collapsed notes, stale data or closure.
Themes can customize `ExplainrSourceContext` (foreground
only), `ExplainrDetailContext`, `ExplainrDetailBackdrop` and `ExplainrDetailActive`.
**K/Enter** or **q/Esc**
collapses onto the currently expanded explanation, not the original entry point.
**n/p** browses entries and synchronizes the source cursor and viewport with the
selected explanation, including both diff sides and old-only deletions.
Detail shows the explanation and intent basis, without
context warnings or separate evidence/anchor lists; range labels and source
gutter markers still identify the referenced lines.
No extra AI call or popup is involved. **Ctrl-e/Ctrl-y** scroll content and notes
together from any paired source or the explainer, even with detail expanded;
counts work too. Native expanded-detail scrolling (including **zz/zt/zb** and
cursor motions that scroll the viewport) moves source panes by the same displayed
row distance, within native buffer limits. The detail cursor remains free for
reading; paragraph lines are never mistaken for source line numbers.
In overview, **q/Esc** closes the pane.

In diff mode, both overview and expanded detail inherit Diffview's file navigation
and explorer bindings: **Tab/Shift-Tab** for next/previous file, **<leader>e** to focus
the explorer, and **<leader>b** to toggle it. Configured remaps, custom actions and
disabled bindings are respected; Explainr keeps its own **Enter/K** controls.
Completed diff explanations are retained per file/comparison for this Neovim run,
including accumulated hunk requests. Switching files exits detail but does not
make the previous file's context stale. Unexplained files show an empty pane;
returning to an explained file rechecks its original context and restores all
accepted notes without another AI call. Real code, decision-document, index or
revision changes still invalidate affected results. In-flight requests for the
file you leave are cancelled; completed results remain available.
Tab is not an Explainr expansion shortcut in either mode.

Set `diff.auto_explain = true` to request a whole-file explanation automatically
when navigating to a Diffview file without valid saved notes, **only while a diff
explanation pane is already open**. Valid saved file/hunk notes are restored
without another AI call; stale saved notes are re-explained on navigation.
Opening Diffview alone or closing Explainr does not start requests. Repeated
layout/focus events, edits on the current file, cancellation and failures do not
automatically retry; use refresh explicitly or navigate to another file.
The default is `false`; enabling it can increase external-agent usage.

While waiting, every active and queued range has a steady, faint full-width tint.
Only a cursor-width `▊` gutter rail animates, with an eased 2.4-second cascading glow.
Accepted notes and text backgrounds remain steady; the focused cursor row pauses
animation. Wrapped/folded rows and diff filler participate too. Source buffers
and Git diff highlights stay untouched by the loader.
For terminal cursor flicker during animation, keep Neovim's default
`vim.opt.termsync = true`. This batches redraws on terminals/multiplexers that
support synchronized output; with it disabled, even updates away from the cursor
can hide/show the terminal cursor every frame. Explainr does not change this
global option or your cursor blinking settings.
Installed
`MeanderingProgrammer/render-markdown.nvim` is used optionally, without changing
your renderer setup; native semantic highlights remain available without it.
The pane has one logical line per source line, including blanks. **j/k** in a
diff traverses insertion/deletion gaps using whichever side has real lines;
passive paired scrolling does not take over navigation while notes have focus.
Other cursor motions work across the whole file; cursors synchronize in both
directions. The overview follows whichever old/new diff source you move in;
notes-driven motion maps paired lines by native diff coordinates.
Page/half-page/mouse scrolling retains wraps, folds and diff filler.
Deletion notes remain reachable at the next surviving line (or EOF). Edits clear
stale notes; refresh is explicit. Loading animates over the requested matching
rows, including diff filler, leaving lualine/the editor statusline alone. Before
diff collection finishes, hunk highlighting is provisional. Errors are reported
through `vim.notify` and `:messages`.

Further requests for the same buffer or loaded comparison accumulate in the
existing pane. Distinct, overlapping scopes can coexist; repeating or refreshing
an identical target updates only that target's batch. While a diff request is
loading, further hunk requests append to a queue without cancelling it. Hunks
and configuration are captured when requested; agent invocations run in order,
one at a time. All pending ranges animate, and status shows the queued count.
Each completed result adds its notes immediately; a failed request does not
block later queued hunks. Other new scopes replace pending work. Cancel and
Refresh clear active/queued work, not accepted notes. Cancellation and ordinary
failures preserve earlier notes. Changes to their code/review context invalidate them;
switching files, modes or comparison ownership starts a separate session.

The UTF-8 byte budget covers the entire prompt, not just source text. Auto/focused
requests omit optional context explicitly, never truncate the selected target.
A target that cannot fit still fails before inference. Bytes are not provider
tokens: lower `max_bytes` or use focused mode if your external tool still rejects
the request. Diff collection and freshness checks use cancellable asynchronous
Git/filesystem operations,
with coalesced checks and yielded processing batches. Cancel/close work during
collection, not just inference. Unrelated oversized files are skipped before
reading their contents in focused mode. Selected versions are still read/diffed
locally in full to locate exact hunks; native hashing/diffing and final prompt
encoding run on the main thread. Valid citations prove that evidence was
supplied, not that an AI explanation is factually correct.

See [`doc/explainr.txt`](doc/explainr.txt) for commands, a live Visual mapping,
configuration, compatibility and limitations; [`doc/explainr-agents.txt`](doc/explainr-agents.txt)
contains restricted OpenCode/Codex/plain/custom transport examples.

## Development

Run the offline suite from the repository root:

```sh
nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'
```

Use normal headless startup, not `-l`: these tests resize and redraw editor
windows, which require normal screen-grid allocation.

No provider credentials or AI calls are required. Select a test file with
`EXPLAINR_TEST=tests/model_test.lua`. Tests for optional integrations document their
dependencies separately; base plugin loading never requires Diffview.

Runtime-tested with Neovim **0.11.5 and 0.12.5** and Diffview revision
`4516612fe98ff56ae0415a259ff6361a89419b0a`. CLI decoding is tested against
documented event contracts using fake processes; no authenticated provider call
or subscription-billing guarantee is claimed.

Optional actual-screen capture (Python `pynvim` and `Pillow`):

```sh
python3 tests/render.py --font /path/to/monospace-font.ttf
```

Captures use fixture explanations and disposable Git reviews, not live AI.
Default output is `.amp/in/artifacts/`; exclude `/.amp/in/` locally before use.
