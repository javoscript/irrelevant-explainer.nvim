# explainr.nvim

AI explanations alongside code and code diffs, with concise row-aligned notes and
in-pane Markdown detail. Requires **Neovim 0.11+**. Diffview is optional for code mode;
code file and visual-selection explanations need no syntax parser.

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
  review = {
    request_max_bytes = 65536, response_max_bytes = 32768,
    max_snapshot_bytes = 16777216, max_requests = 128,
  },
  cache = { enabled = true, max_bytes = 104857600, namespace = "default" },
  -- cache.decoder_key = "my-decoder-v1" -- Required for custom-decoder disk reuse.
})
```

The `explain` agent is user-created and should deny edits and unnecessary tools.
Explainr does not manage credentials, guarantee subscription billing, or sandbox
arbitrary commands. Provider permissions, billing, and retained history belong to
the configured tool.

## Usage

```vim
:Explainr [file|selection|hunk|review]
:'<,'>Explainr selection
:Explainr hunk
:Explainr review
:ExplainrReview
:ExplainrRefresh
:ExplainrCancel
:ExplainrClose
:ExplainrCacheClear
```

`Explainr` defaults to `file`; Lua uses `require("explainr").explain(scope, selection)`.
File scope explains current code in an ordinary source window, or changes in a
Diffview source window. Ownership is by **window**, even when both show the same
buffer; Git changes or native vimdiff alone do not imply diff mode. Notes/detail
use their followed source, not Markdown. Selection always explains exact selected
source text; hunk requires a coherent Diffview source. File/hunk cannot target
the file tree, and loading/unsupported views fail rather than fall back to code.

**Migration:** replace `ExplainrCode` / `ExplainrDiff` with `Explainr`, and public
`code()` / `diff()` calls with `explain()`; no compatibility aliases remain.
Function/class scopes are also removed: select the desired region yourself,
then use `:'<,'>Explainr selection`, or `file` for the whole buffer. Retired scopes
report an error and never broaden the target. Restart Neovim after migrating.
See `:help explainr-commands` for a Visual mapping that captures exact endpoints.

**`:Explainr review` runs a bounded whole-change job:** sequential annotation,
optional reduction, and final synthesis calls produce a narrative connecting the
files plus notes for every eligible text file, installed together. The right-hand
pane opens in **Review** mode, with independently scrollable Markdown. Enter on
a generated file-reference row selects that exact Diffview entry and shows its
aligned **File** notes. Enter on ordinary prose does nothing. Esc returns to
File overview; q closes the reader.
In Review, **Ctrl-e/Ctrl-y** scroll by one visible row, including wrapped lines;
counts use the same unit (for example, **3Ctrl-e** scrolls three visible rows).
Source windows stay still, and returning to File restores its scrolling setting.
You can generate or open Review from either source pane or the Diffview file
tree (`DiffviewFiles`); tree focus and the selected comparison stay unchanged.

Outside Diffview, `Explainr review` opens a new repository-wide **HEAD-to-working
tree** comparison for the named source's repository/worktree (an unnamed source
uses its window's effective cwd). This is the net staged-plus-unstaged change:
an unstaged undo can cancel a staged edit. Existing comparisons keep their exact
revisions, selected staged/working set and path filters. New reviews respect
Diffview's untracked-file policy; excluded untracked/ignored files are not added.
The tested Diffview version excludes untracked files from HEAD comparisons;
staged additions are tracked and remain included.
Unsaved buffers overlay working-side files already in the comparison manifest,
not unsaved-only files absent from it. Nothing is autosaved or staged.

Opening is asynchronous and cancellable with `ExplainrCancel`/`ExplainrClose`
from the origin or new view. Inference waits for coherent sources; repeated
opening requests coalesce. Cancellation/failure leaves an opened Diffview tab
intact. Missing dependencies, repository/HEAD, eligible text, or incompatible
Diffview defaults report an error rather than substitute another comparison.

**`:ExplainrReview` only opens the narrative** (Lua: `require("explainr").review()`),
without an AI request. It restores your reading position or shows an explicit
empty/pending/failed/stale state. It requires an existing supported comparison
and never opens Diffview. The pane-local `<Plug>(ExplainrReview)` action
is available for user mappings; the plugin adds no global shortcut. For example:

```lua
vim.keymap.set("n", "<leader>av", "<cmd>Explainr review<cr>", { desc = "Explain whole diff" })
vim.keymap.set("n", "<leader>aV", "<cmd>ExplainrReview<cr>", { desc = "Read change narrative" })
```

Review scope requires complete **job-wide** source coverage regardless of
`context.diff`, not simultaneous whole-source reasoning in every call. A frozen
snapshot may exceed one prompt: affordable whole-file units are grouped, oversized
files/hunks split at original line coordinates, and cited original text accompanies
findings through reduction/synthesis. Binary and empty entries remain metadata.
Split fragments cannot return whole-file overviews. Coverage is not proof that
the model understood every line or found every relationship.

Each complete prompt fits `min(context.max_bytes, review.request_max_bytes)`;
`response_max_bytes` bounds decoded JSON per call. `max_snapshot_bytes` admits
canonical serialized local review data (not Lua heap size), and `max_requests`
bounds new calls across all phases in each explicit run/resume. All four are
positive finite integers; `ai.timeout_ms` applies per call. Increasing only
`context.max_bytes` does not enlarge review batches. An indivisible source line,
finding/evidence packet, or mandatory manifest that cannot fit fails explicitly.
These are UTF-8 byte guardrails, not provider token/output controls, capacity
guarantees, or a fix for OpenCode compaction. Smaller limits or a filtered
comparison/file/hunk scope may be needed. Multiple calls can add latency and cost.

Custom wrappers must support **version 3** `annotate`, `reduce`, and `synthesize`
envelopes; code/file/hunk retain version 1. Version 2 is internal final assembly
only, not accepted review wire output. See `:help explainr-agent-review`.
Invalid/truncated output stops the job without automatic repair or fallback and
without displaying a partial new review; earlier fresh accepted notes survive.

Repeat `:Explainr review` **in the owning comparison or its reader** to recollect,
revalidate and resume matching successful in-memory checkpoints, retrying failed
and unstarted calls. Cancel keeps validated checkpoints while that owner remains
open; Close, stale/replaced comparisons and restart discard unfinished work.
Review Refresh discards checkpoints and regenerates every phase. A new request
from ordinary code opens a new comparison, not another owner's unfinished job;
repeats during opening only coalesce. Completed exact cache hits can cross owners.

### Completed-result cache

All five scopes share an enabled-by-default persistent cache (100 MiB configured
limit), in addition to in-memory reuse. Freshly captured source, exact target and
coverage, comparison, worktree and generation settings must match. Equivalent
manual and automatic review opening can share completed answers after readiness;
hits are validated before display and invoke no agent. Review records replay
phase validation locally against reconstructed requests, not external inference.

Records are private **plaintext JSON** at
`stdpath("cache")/explainr/results/v1/<source-hash>/<request-key>.json`.
Created directories/files use 0700/0600 where supported. No full snapshots, prompts,
raw argv or process streams are stored, but result prose can contain sensitive
source snippets: private permissions are not encryption. Atomic writes and
least-recently-used pruning manage retention; oversized entries are skipped and
cache failures do not fail valid explanations. Simultaneous processes may both
infer on a miss; the configured budget is not a hard whole-directory capacity
guarantee including temporary files or external interference.

Set `cache.enabled = false` to disable disk reads/writes (not memory retention).
Custom `ai.output` functions opt out of disk reuse unless you supply a stable,
nonempty `cache.decoder_key`. Change it when the decoder changes. Explainr cannot
detect provider/agent settings hidden in environment, external config or wrapper
scripts: change `cache.namespace` (a nonempty string) or explicitly Refresh when
those change. Command argv is hashed for identity, not saved as plaintext config.

`:ExplainrCacheClear` / `require("explainr").clear_cache()` clears owned completed
disk entries and reusable memory answers without closing readers or removing
displayed valid notes. It does not clear unfinished checkpoints; use Review
Refresh for those. Pre-clear work in this process cannot repopulate the cache,
but another Neovim can create later entries. Refresh bypasses memory and disk
answers for its scope and replaces an old disk answer **only after success**.

Code mode uses current unsaved buffer text, with the whole buffer as context
for visual selections. File/hunk diff mode follows a loaded two-way Diffview source and
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
all its content. No overview is requested for selection or hunk
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
clears collapsed focus. After collapse, focus follows the destination row's
summary, if any, rather than forcing the cursor back to the expanded explanation.
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
You can also expand from any row within an explanation's original anchor ranges,
including context before a relocated diff summary. A visible summary takes
precedence; on a blank row, a single local explanation opens directly even when
a whole-file overview also covers it. Multiple local explanations open a
`vim.ui.select` chooser with summaries and original range labels, local notes
first and the overview last. Cancelling leaves the pane collapsed. If only the
overview covers the row, it opens directly; closed summary folds still expand
together. Expansion itself never moves the source cursor or viewport.
Following notes keep their aligned rows when space allows; a longer card puts
them below its body instead of hiding them. A fixed gutter with one padding
space prevents horizontal shifts on expansion/collapse.
Surrounding context is strongly dimmed and the expanded
body has a subtle neutral surface tint from the active colorscheme's `CursorLine`
background, softened toward `Normal`. Themes without that background use
`NormalFloat` or a faint blend of the normal text color. The gutter and left
padding stay on the dimmed backdrop, outside the tinted content.
The summary, range label, metadata
and wrapped prose margins share that background; code fences stay visible and
installed language parsers provide code syntax colors. A continuous `▎`
gutter rail covers the expanded explanation, including wrapped lines, connecting
it visually to the referenced source ranges. The rail and tint extend through
the visible anchored range even past neighboring summaries, whose text stays
dimmed. A whole-file overview therefore covers the whole visible file extent.
Near the bottom, the card lifts enough to show the
first explanation line without moving code. The referenced code is temporarily
marked with a muted gutter rail; text outside the anchors is dimmed in the source
windows (both sides in diff mode). Other splits or tabs showing the same buffers
remain undecorated. Anchored syntax colors, Git diff backgrounds
and existing signs stay intact. Native diff foregrounds take precedence over
dimming, so changed text can remain brighter outside the anchors.
Focus follows **n/p** and the collapsed destination; it clears on a blank row,
departure from collapsed notes, stale data or closure.
Themes can customize `ExplainrSourceContext` (foreground
only), `ExplainrDetailContext`, `ExplainrDetailBackdrop` and `ExplainrDetailActive`.
**K/Enter** or **q/Esc**
collapses at the current source-aligned line, not the summary or original entry
point, while preserving source viewports and pane focus within native geometry
limits. Wrapped prose uses its display position, never its Markdown line number;
outside visible anchors the nearest eligible position is used. With all anchors
off-screen, the native source position is retained. Immediately collapsing
without reading motion keeps the source position established on opening or n/p
navigation. Enter/K in detail never opens the overlap chooser.
**n/p** browses entries and synchronizes the source cursor and viewport with the
selected explanation, including both diff sides and old-only deletions.
Detail shows the explanation and intent basis, without
context warnings or separate evidence/anchor lists; range labels and source
gutter markers still identify the referenced lines.
Detail needs no extra AI call or popup. When you scroll code, expanded detail
follows its summary until it reaches an edge, then sticks inside the explanation
viewport below the header. A fitting card stays wholly visible; longer detail
keeps your prose reading position, with every paragraph reachable. Scrolling back
releases the card into natural alignment without moving code again or changing
the selected explanation.
In expanded detail, **j/k** move by displayed row, including counts: **4j** moves
four screen rows, not four paragraphs. These buffer-local mappings do not use
global j/k remappings; native **gj/gk**, other motions, and overview/source
navigation remain unchanged.
Scrolling the explanation still scrolls code, even while pinned: **Ctrl-e/Ctrl-y**
(including counts), **zz/zt/zb**, page/half-page and cursor-induced viewport motion
move sources by the actual displayed-row distance, within native buffer limits.
At the reader's upper buffer limit, **Ctrl-y** still scrolls code upward; **k**
on the summary's first displayed segment at the top screen edge does the same without collapsing detail
or jumping to stale context. Both accept counts and stop at the source's beginning.
If a fitting card has reached its bottom placement limit, a further **Ctrl-y**
from inside it moves to the source-backed row immediately above the card instead
of getting stuck. Leaving the active anchors collapses at that destination;
anchored context stays expanded. A counted command stops at this escape destination
without applying leftover steps. Simply reaching an edge, scrolling code, or
hitting a genuine file boundary does not collapse detail. Longer prose remains
fully scrollable, and top-pinned reading settles without a scroll-and-snap-back frame.
On later summary wraps, **k** reads the preceding segment instead, even if that
later segment is clipped to the top edge.
Source `scrolloff` is respected, including different margins on diff sides,
without duplicate margin-correction scrolls. In overview, code and notes still
scroll together. Expanded reading scrolls also select the final source-aligned
cursor target, even when sticky-edge scrolling leaves the reader cursor still.
Selection preserves the completed source viewport and original `scrolloff` values;
source-driven scrolling never applies the inactive reader cursor to code.
Moving through expanded summaries,
metadata or prose also selects the source line beside the cursor's display row,
including wrapped prose, source wraps, folds and old-only diff deletions. Targets
stay within the expanded anchors: prose beyond them selects the nearest visible
anchored row, with ties choosing the earlier row. If all anchors scroll off-screen,
reading continues without snapping code back. Paragraph buffer line numbers are
never treated as source line numbers. Blank anchored continuation still follows
code; entering surrounding context outside the anchors collapses at that destination.
In overview, **q/Esc** closes the pane.

In diff mode, Review, File overview and expanded detail inherit Diffview's file navigation
and explorer bindings: **Tab/Shift-Tab** for next/previous file, **<leader>e** to focus
the explorer, and **<leader>b** to toggle it. Configured remaps, custom actions and
disabled bindings are respected; Explainr keeps its own **Enter/K** controls.
Completed diff explanations are retained per file/comparison for this Neovim run,
including accumulated hunk requests. Switching files exits detail but does not
make the previous file's context stale. Unexplained files show an empty pane;
returning to an explained file rechecks its original context and restores all
accepted notes without another AI call. Real code, decision-document, index or
revision changes still invalidate affected results. In-flight requests keep
running after file navigation, including during collection. Off-screen results
are retained for their original file and never replace another file's notes.
Returning to a pending file reconnects to that request without duplicate inference.
Tab is not an Explainr expansion shortcut in either mode.

Set `diff.auto_explain = true` to request a whole-file explanation automatically
when navigating to a Diffview file without valid saved notes, **only while a diff
explanation pane is already open**. Valid saved file/hunk notes are restored
without another AI call; stale saved notes are re-explained on navigation.
Opening Diffview alone or closing Explainr does not start requests. Repeated
layout/focus events, edits on the current file, cancellation and failures do not
automatically retry; use refresh explicitly or navigate to another file.
The default is `false`; enabling it can increase external-agent usage.

Use **`:ExplainrToggleAutoExplain`** or `require("explainr").toggle_auto_explain()`
to switch automatic explanations on/off without running setup again. The Lua
function returns the new boolean; both entrypoints notify the new mode. The
setting applies across tabs for this Neovim process, with setup providing its
initial value. Enabling affects **subsequent navigation only**, not the current
file or an earlier file switch still loading/checking saved notes. Disabling
preserves notes and already-started requests; use `:ExplainrCancel` to stop work.
It drops only unstarted automatic candidates. While busy, Auto keeps the latest
visited unexplained file as one candidate; explicit requests take priority.
Queued/running reviews suppress redundant automatic requests. Review failure
does not fan out into per-file retries.
Manual requests, refresh, and saved-note restoration work in either mode.

Enabled diff panes show **Auto** beside the explanation count in their winbar,
in overview and expanded detail, including pending and terminal states. It
indicates enabled navigation automation, not a running request. Toggling updates
all open diff headers immediately without collapsing detail or moving focus.
Code panes omit it, and your editor statusline/lualine remains untouched.
The mode is not persisted across restarts. No global mapping is installed;
an optional user-defined keybind is:

```lua
vim.keymap.set("n", "<leader>ea", "<cmd>ExplainrToggleAutoExplain<CR>", {
  desc = "Toggle Explainr automatic explanations",
})
```

While waiting, every active and queued range has a steady, faint full-width tint.
Only a cursor-width `▊` gutter rail animates, with an eased 2.4-second cascading glow.
Accepted notes and text backgrounds remain steady; the focused logical cursor
line keeps a steady rail across its wraps while other eligible rails animate.
Wrapped/folded rows and diff filler participate too. Checking saved File
explanations loads the visible file extent without launching inference. Review
checks animate retained prose or its placeholder, with continuous rails through
wrapped paragraphs, blank lines, and empty viewport space. Source buffers and
Git diff highlights stay untouched by the loader.
Every busy phase shows an animated header spinner, including saved-result checks,
cache lookup and result-context validation, even with focus or expanded detail.
Background work is identified separately and does not tint unrelated File notes.
The spinner indicates activity, not a provider call, percentage, or ETA.
For terminal cursor flicker during animation, keep Neovim's default
`vim.opt.termsync = true`. This batches redraws on terminals/multiplexers that
support synchronized output; with it disabled, even updates away from the cursor
can hide/show the terminal cursor every frame. Explainr does not change this
global option or your cursor blinking settings.
Both overview and detail use the `explainr` filetype with optional Markdown
Tree-sitter highlighting. The `markdown` and `markdown_inline` parsers highlight
structure and inline code; installed language parsers highlight fenced snippets.
Markdown markers remain visible, and detail wraps natively without renderer
padding, borders, or concealment. Missing parsers leave readable semantic styling;
Explainr does not install parsers or invoke `render-markdown.nvim`. Your renderer
configuration and ordinary Markdown buffers remain unchanged.
The collapsed pane has one logical line per source line, including blanks. **j/k** in a
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
loading, explicit file, hunk and review requests append to a queue without cancelling it. Targets
and configuration are captured when requested; agent invocations run in order,
one at a time, deduplicating equivalent pending requests. Only ranges for the
displayed file animate; status distinguishes current, background and queued work.
Each completed result adds its notes immediately; a failed request does not
block later queued requests. Code requests still replace pending code work. Cancel and
Refresh clear active/queued work, not accepted notes. Cancellation and ordinary
failures preserve earlier notes. Changes to their code/review context invalidate them;
switching comparison ownership or code/diff modes starts a separate session.
Refresh acts on the visible mode: Review regenerates narrative and all files;
File requests only its file/hunk, even when its notes came from a review.
Background completion preserves open detail and narrative position. A fresh
replacement for an expanded note appears after you leave detail; stale notes
are cleared immediately. Cancel/Close stop all owned pending work across files.

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
