# Design

## Context

See proposal.md for the reported sequence and scope. A design is included because the unsafe expression is confirmed, but its triggering lifecycle transition is not.

`pane:detail()` in `lua/explainr/ui.lua` installs a window-local `statuscolumn` that directly reads `b:explainr_detail_active`. `pane:decorate_detail_context()` populates that dictionary on the detail buffer. The dictionary is initialized later than the expression, and a different buffer need not have it at all.

`pane:back()` swaps to the overview and restores saved options. The isolated normal-collapse probe restored the gutter successfully; the source order alone is not evidence that this path fails. A separate probe replacing the displayed detail buffer with a fresh buffer retained the expression and reproduced both reported errors. `pane:close()` can create a replacement window from the last reader before closing it, and an existing UI test explicitly avoids inheriting reader options in that case.

Diff sessions follow changed selections through `session.lua` into `pane:set()` and detail cleanup, before saved-note restoration or optional inference. Existing tests cover much of that behavior, but do not directly evaluate a detail gutter against a buffer without its dictionary. The user's report confirms prior expansion, not whether detail remained expanded at the switch.

## Goals / Non-Goals

**Goals:**
- Make the expression safe independently of callback timing, and make ownership checks detect leakage even when that safety guard hides its error.
- Preserve native gutter rendering and constrain lifecycle edits to the paths shown to violate ownership.

**Non-Goals:**
- Redesign the reader, session state machine, Diffview layout, or auto-explain policy.
- Initialize Explainr data on every editor buffer, suppress editor errors globally, or reset unrelated window options.
- Change public commands, configuration, or inference prompts.

## Decisions

### Guard the expression at its point of evaluation

Use a short-circuit existence check before dictionary lookup, for example `exists('b:explainr_detail_active') && get(b:explainr_detail_active, string(v:lnum), 0)`. Missing data takes the existing blank-gutter branch; valid data keeps the current rail and padding. This avoids requiring every transient buffer to be initialized.

Test the complete `%{...}` statuscolumn format through Neovim, not just the inner Vimscript expression. An inline empty-dictionary fallback was investigated and its closing brace prematurely terminated this format expression; the existence-check form evaluated successfully for absent, empty, and active data. Initializing only the detail buffer earlier is insufficient because other buffers can still lack the variable. Replacing the native gutter with signs would change wrapped-row behavior unnecessarily.

### Repair ownership at the existing lifecycle boundaries

Instrument the targeted regression sequences to observe the displayed buffer and effective gutter on the reader, source, and explorer windows during expansion, explicit collapse, explorer selection, and cleanup. Include last-window replacement as a concrete inheritance risk. Compare distinct preexisting gutter values, not only empty defaults.

Keep the expression attached only to detail content; restore or scope owned gutter options at the existing creation/collapse/cleanup boundaries wherever the tests expose leakage. Account for Neovim's buffer-switch and split option inheritance instead of assuming that moving a setter before a buffer swap fixes it. Preserve the existing detail guard against synchronizing Markdown cursor positions into replacement code buffers. Do not add an editor-wide autocmd or a new option-management abstraction for this localized behavior.

### Exercise real navigation while keeping inference offline

Extend `tests/ui_test.lua` with direct missing-data evaluation, valid rail rendering, and lifecycle/cleanup assertions. `nvim_eval_statusline` can emit Vim errors while returning successfully, so inspect the emitted errors or `vim.v.errmsg` as well as output; a successful `pcall` is not enough.

Extend `tests/diffview_test.lua` using the existing `tests/review.lua` fixture and stubbed agent responses. Exercise explorer focus and file selection, not solely synthetic session events. Cover expanded versus explicitly collapsed detail and runtime-enabled versus disabled auto-explain. Observe transitions and force redraw, then assert settled gutter ownership, old detail disposal, preserved source settings/focus, and the existing request/restoration counts. Repeat navigation/events to expose retained options and avoid timing-only assertions.

## Risks / Trade-offs

- A missing-data guard could hide option leakage → assert gutter ownership and preserved custom values separately from absence of errors.
- The original Diffview sequence may depend on layout or Neovim timing → retain the deterministic buffer-replacement regression and report whether real explorer navigation reproduces the original failure before the fix.
- Cleanup changes could affect cursor synchronization or user options → keep existing buffer-validity guards, verify different source/overview gutter values, and run the UI and real Diffview suites plus the full suite.
- Headless checks can miss redraw-dependent behavior → use the existing screen-grid capture workflow (`tests/render.py` and `tests/visual.lua`) to inspect wrapped detail, the overview after switching, and any affected surviving-window state. Keep captures in the repository's locally excluded artifact directory.

## Migration Plan

No data or configuration migration is needed. The fix ships as a normal plugin update; restarting Neovim loads it without relying on hot-reload cleanup of already-contaminated windows. Reverting the scoped code change restores the previous behavior.

## Open Questions

- Which exact explorer/layout transition retained the gutter in the reported session? The bounded integration tests above will establish what is reproducible; the safety and ownership requirements do not depend on that answer.
