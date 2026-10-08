# Design

## Context

See `proposal.md` for motivation and `specs/aligned-explanation-ui/spec.md` for the behavior contract.

`session.lua` owns request, retained-result, restoration, and freshness lifecycles. Its renderer distinguishes selected requests from background work, while `follow()` restores saved file batches without a pending inference request. Restoration emits `Checking saved explanations`; new display-only readers can emit `Checking saved review`. Request phases already use `Pending`, including `checking completed cache` and `checking result context`.

`ui.lua` separately checks the `Pending` prefix in timers, loaders, and headers. Headers suppress spinners when the pane has focus; narrow annotation headers can discard the spinner; detail headers lack one and `pane:state()` returns before updating detail. Review loading places one sign per logical Markdown line, which does not repeat across wrapped screen rows. Existing detail gutters use a buffer-safe, window-local status-column expression that does repeat on wrapped rows. Review already reserves two gutter cells while idle.

Exploration reproduced the missing wrap rails and the idle timers for both saved-result status labels in Neovim 0.12.5. Existing UI tests assert that the focused logical line is skipped, so they must deliberately change alongside the spec rather than mask a regression.

## Goals / Non-Goals

**Goals:**
- Reuse session ownership and existing render/timer paths instead of introducing a second activity state machine.
- Separate header activity from eligible body loading: background work can spin without tinting unrelated content.
- Maintain fixed gutter width, native wrapping, accepted text, cursor/viewport positions, and source options across loading transitions.

**Non-Goals:**
- Change cache identity, result acceptance, cancellation, queuing, automatic inference, or review progress accounting.
- Display unvalidated retained content earlier than current freshness rules permit.
- Add body animation to expanded detail; its existing anchor styling stays intact while the header reports activity.
- Expose silent periodic freshness polling as a permanent busy state, add a theme/configuration API, or change global cursor/terminal options.

## Decisions

### 1. Share busy classification, but keep ownership in the session

Use one UI-local classification for the existing user-visible `Pending` and `Checking` states. Collection, request, processing, and review phases already fall under `Pending`; do not maintain a list of natural-language verbs or invent provider thinking events. Keep status strings and `vim.b.explainr_status` undecorated.

Have `session.render()` expose selected-file restoration and genuinely active/queued background work explicitly where status alone is insufficient. Restoration must remain scoped to the current `review_key`, including its wait for coherent Diffview panes. Do not create a fake pending request merely to satisfy the loader's current request gate. Preserve the normal hidden-narrative placeholder when a newly opened reader has not validated saved content. Display-only reopening of already displayed prose can indicate its owned check without replacing the narrative or resetting its view.

Alternative: normalize every status to `Pending` and derive all body loading from it. Rejected because restoration has no request anchors and background strings alone do not establish the selected target's eligibility. An explicit restoration/background signal plus a small shared status predicate is sufficient; a general activity model is not needed.

### 2. Update busy headers independently of body/detail rendering

Keep the existing timer, but let header updates run in File overview, Review, and expanded detail regardless of focus. Detail ticks must not rebuild or place the detail card. Body loading still follows mode-specific eligibility. Start/stop animation from current status and owned background/restoration signals; preserve the timer-identity check for late scheduled callbacks.

Reserve spinner width while choosing header segments. Retain existing count/mode/Auto priorities; when there is room, keep the spinner and an abbreviated phase before brand, legend, navigation hints, bar, or background descriptions. Narrow Review should retain `Annotating N%` alongside the spinner rather than dropping activity to keep secondary text. Extremely narrow panes can omit lower-priority elements without overflow. Keep background-work identification when displayed content itself is idle.

Alternative: preserve the focus-dependent header pause to avoid all terminal redraws. Rejected because it makes a focused reader appear idle. Cursor protection belongs in the body rail, not in a header away from the text cursor.

### 3. Render Review rails in its reserved native gutter

Replace loading sign glyphs on narrative lines with a fixed two-cell, buffer-safe Review status-column gutter, following the existing detail-gutter pattern. Prepare only visible line decoration data and update its glow on ticks; native gutter rendering repeats the glyph across each paragraph's wraps, including when the paragraph begins above the viewport. Keep steady line tint separate from the gutter so text and syntax remain untouched. Preserve the current EOF empty-viewport decoration strategy, with the same rail/padding/tint width as narrative rows.

Use window-local options on the Review buffer and restore File options on return. Missing gutter data during buffer transitions must render blank rather than error. Clear Review data/decorations on terminal transitions, mode exit, and close. Cursor motion, scrolling, and resize must refresh visible gutter eligibility without source synchronization; current Review early-return event paths need a lightweight decoration/header update, not a File geometry rebuild.

Alternative: overlay each wrapped text row or rewrite prose into physical lines. Rejected because overlays risk text/highlight damage and physical line splitting changes wrapping, references, and saved reading positions. Merely adding more sign extmarks cannot mark wrapped segments of the same logical line.

### 4. Restoration uses visible-file coverage; inference retains target ranges

While selected saved File explanations are being checked, treat its displayed file extent as eligible loading coverage, independently of a pending request. Once replacement source panes are coherent, use their current cached projection/comparison coordinates, including wraps, folds, and diff filler. Before coherence, indicate checking in the header and reader placeholder without using the previous file's anchors. Re-render when the new coherent source becomes available so the loader follows the correct geometry.

Ordinary file/hunk requests continue to use matching active/queued targets and existing provisional ranges. A background review does not tint accepted File content just because Review itself is busy. Navigation retires the old restoration and decoration ownership; late callbacks remain subject to existing generation/key checks.

Alternative: restore notes optimistically to obtain anchors for the loader. Rejected because loading feedback must not weaken freshness validation.

### 5. Freeze the focused logical line's rail, not its presence

Capture a stable glow intensity for the focused logical line, applying it to its visible wrapped segments as well. Other eligible rails advance normally; header frames continue. On cursor movement, resume the old line and freeze the new one; clear freeze data on mode/target changes and loading cleanup. Avoid animated overlay replacement of accepted text on the cursor line. Keep backgrounds steady and retain the existing synchronized-output caveat rather than promising flicker-free terminals.

Alternative: continue omitting the cursor line's entire rail. Rejected because it leaves a large visual gap when the cursor is in a long wrapped paragraph. Freezing only the header would not fix that gap.

## Risks / Trade-offs

- Status/gutter expressions may evaluate during buffer replacement → Guard absent buffer data, keep options window-local, and exercise Review/File/detail/close transitions.
- A focused paragraph can cover most of the viewport, leaving little body motion → Its rail remains continuous and the header always supplies visible activity.
- Review scroll/resize events currently skip several File update paths → Add lightweight Review decoration updates and test clipped first wraps and width changes without resetting the view.
- Animation could start scanning entire source files or rewriting buffers on each tick → Reuse cached File geometry and visible Review decoration data; assert stable changedticks and no File render/whole-file scans during ticks.
- Periodic freshness checks or stale background labels could keep spinners alive → Derive background/restoration signals from owned work and expose only user-visible checks; test all terminal states and late callbacks.
- Continuous header animation can still flicker on terminals without synchronized redraw → Keep `termsync` and `guicursor` untouched and document the limitation.

## Migration Plan

No data migration or new dependencies are required. Implement with failing screen/ownership regressions first, update loader documentation, then run the offline suite and inspect captures from the existing `tests/render.py` workflow. Exercise supported Neovim 0.11 and 0.12 installations when available. Rollback is reverting the implementation and its spec delta; completed-result caches remain compatible.
