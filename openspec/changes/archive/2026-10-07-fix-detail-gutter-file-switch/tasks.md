# Tasks

## 1. Safe gutter evaluation and local lifecycle

- [x] 1.1 Add a deterministic regression in `tests/ui_test.lua` using the actual detail statuscolumn on a replacement buffer without decoration data; force evaluation/redraw and verify the pre-fix failure includes `E121`/`E116`, checking editor errors rather than only Lua call success.
- [x] 1.2 Guard missing detail data in `lua/explainr/ui.lua`; verify absent and empty dictionaries produce no rail or errors, active/inactive rows remain distinct, and the existing wrapped-detail rail and padding assertions pass.
- [x] 1.3 Add lifecycle coverage for expand/collapse/re-expand, result replacement, source closure, and last-reader-window cleanup with distinct custom gutter values. Correct demonstrated gutter inheritance/restoration defects at existing UI boundaries, and verify overview restoration, no detail expression on surviving ordinary windows, and unchanged source gutters. Run `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`.

## 2. Diffview explorer navigation regression

- [x] 2.1 Extend the offline real-Diffview tests to open explanations, expand a note, optionally collapse it, focus the explorer, and select another file with automation disabled or enabled via the runtime toggle after pane opening. Observe buffer/gutter transitions and force redraw; record whether the original error reproduces in these real navigation paths independently of the deterministic UI reproduction.
- [x] 2.2 Fix any additional gutter ownership defect exposed by those sequences within the existing UI lifecycle, and make the regressions assert no emitted gutter errors, no stale detail buffer/rail, preserved source/explorer gutter settings and navigation focus, and no old-detail cursor applied to replacement code buffers. Verify both expanded-at-switch and collapsed-before-switch variants pass.
- [x] 2.3 In the same navigation coverage, assert toggling alone launches nothing, enabled navigation launches exactly one file request, disabled navigation launches none, unchanged saved notes restore without inference, and repeated events do not duplicate work. Run `EXPLAINR_TEST=tests/diffview_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` with the real Diffview dependency present; a skipped integration suite does not count as passing.

## 3. Combined verification

- [x] 3.1 Run `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` and verify the full suite passes, including existing retention, cancellation, stale-result rejection, toggle, and source-isolation checks.
- [x] 3.2 Use the existing Neovim screen-grid capture workflow to render and inspect wrapped expanded detail and the overview after explorer navigation, plus a surviving cleanup window if its options changed. Verify rail coverage/padding, absence of stale rails and error prompts, and preserved source gutters; retain inspected captures under `.amp/in/artifacts/` after confirming `/.amp/in/` is locally excluded. Report any capture limitation rather than claiming visual verification.

## Investigation evidence

The deterministic missing-data regression reproduced E121/E116 before the fix. The lifecycle regression also detected the detail expression becoming a default for replacement buffers. The four real explorer-navigation variants pass with both the original and fixed UI module on this machine, so the user's precise trigger remains unconfirmed. Source-gutter comparisons use a native Diffview baseline: first-time working-file loading can inherit the explorer gutter even without Explainr; the fix does not override that behavior.

Final verification: 257 main-suite tests and 16 isolated real-Diffview tests passed. Captures for `diff-gutter-switch`, `diff-gutter-detail`, `diff-gutter-collapsed-switch`, and `gutter-cleanup` were rendered with `tests/render.py` and inspected under `.amp/in/artifacts/gutter/`. Local-only gutter assignment also prevents last-window replacement inheritance, so no separate cleanup setter was needed.
