# Tasks

## 1. Settle expanded scrolling without corrective frames

- [x] 1.1 Add a deterministic top-pinned fitting-card fixture using actual mapped Ctrl-e input and queued events in `tests/ui_test.lua`, plus attached-UI frame capture through `tests/visual.lua` / `tests/render.py`; identify the first native or deferred step that displaces and restores the card, and verify the regression observes intermediate flushed frames rather than only final state.
- [x] 1.2 Update `pane:scroll()` and placement/reconciliation in `lua/explainr/ui.lua` so mapped input completes final geometry, source selection, and cached views without a later corrective frame; verify single and repeated Ctrl-e, paired movement exactly once, genuine native no-ops, and unchanged state after repeated CursorMoved/WinScrolled/SafeState events using the group 1 regression and `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`.
- [x] 1.3 Verify and, where needed, extend existing long-prose, source-driven sticky, and inherited/local/unequal scrolloff regressions to show that the fix does not clamp legitimate reading offsets or change source options; inspect captured top-edge frames and record the no-correction result without claiming a final screenshot alone proves absence of flicker.

## 2. Escape a placement-blocked card into context

- [x] 2.1 Add reader Ctrl-y boundary regressions one step before, exactly at, and one step beyond the fitting-card bottom limit, including an inside-anchor predecessor and an outside-anchor predecessor; verify expected destination, detail state, source viewport, focus, and no automatic neighboring expansion, then implement preflight escape through current context ownership and the existing collapse lifecycle in `lua/explainr/ui.lua` until those checks pass.
- [x] 2.2 Handle counts that end before, at, or beyond the limit, stopping at the first escape destination without replaying leftover input; verify counted and repeated-key results against explicit expected positions, that further context navigation is not reset to the escape row, and that the existing top-edge k shortcut remains unchanged.
- [x] 2.3 Extend targeted regressions for wrapped/folded context, old-only deletion ownership, genuine source BOF, a viewport-filling card with no preceding row, and taller prose; verify native source-driven scrolling never triggers the reader escape, all long prose stays reachable, and repeated deferred events cannot undo or repeat an escape.
- [x] 2.4 Update expanded scrolling guidance in `README.md` and `doc/explainr.txt` for the reader-only boundary escape, anchor-dependent collapse, and stop-at-escape count rule; verify the documented examples against the boundary fixtures, and capture/inspect the bottom-pinned state followed by its collapsed source-aligned destination using the actual UI-grid workflow.

## 3. Combined validation

- [x] 3.1 Run `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` and `openspec validate fix-expanded-scroll-boundaries --strict`; verify the combined scroll, navigation, diff, and lifecycle suites pass, review that only scoped files changed, and report any unavailable runtime or visual checks alongside inspected artifacts stored under locally excluded `.amp/in/artifacts/`.
