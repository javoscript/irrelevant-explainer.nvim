# Tasks

## 1. Expanded visual-row cursor synchronization

- [x] 1.1 Add a regression in `tests/ui_test.lua` with a 37–58 anchor and prose beside source line 42; verify native cursor movement without a viewport delta fails on the current implementation because the source remains at 37, and assert unchanged source views, expanded entry and focus.
- [x] 1.2 Extend the explanation-driven prose branch in `lua/explainr/ui.lua` to use the actual cursor display row after paired scrolling, retain expanded anchor ranges and select the nearest visible eligible target; verify the regression passes and add boundary, disjoint-anchor tie and EOF cases that would fail for raw Markdown-row mapping or unbounded selection.
- [x] 1.3 Reuse existing comparison/fold resolution for prose targets and add asymmetric geometry cases in `tests/ui_test.lua`: later wrapped segments of the same paragraph, wrapped source lines, a fold starting before its anchor, old-only deleted lines and combined folded entries; verify exact source lines, native paired diff coordinates, preserved source columns where valid and unchanged fold/wrap/diff membership.
- [x] 1.4 Guard and refresh final cursor/view state so repeated CursorMoved, WinScrolled and SafeState events cannot replay motion; verify expansion and n/p initialization do not move code unexpectedly, source-driven motion is not overridden, scrolloff does not cause an extra viewport shift, and the existing long-prose scrolling, continuation, collapse-at-destination and entry-navigation tests still pass. Add an explicit off-screen-anchor assertion to the long-prose test.
- [x] 1.5 Update `README.md` and `doc/explainr.txt` to describe anchor-bounded visual-row synchronization, the off-screen-anchor exception and unchanged free reading/context collapse; verify neither document still claims ordinary expanded prose cursor movement is always independent of code.

## 2. Integration verification

- [x] 2.1 Run `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`, then the full offline suite with `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`; verify passing results or identify any independently reproducible pre-existing failures without suppressing them.
- [x] 2.2 Exercise the 37–58 diff case and a wrapped-prose case in a rendered Neovim session using the existing screen-capture workflow in `tests/render.py`/`tests/visual.lua`; inspect captures showing the source selection follows the prose row while anchored and remains bounded past the anchor. Check optional Markdown rendering when available, and report any unavailable dependency instead of treating an unexecuted check as passing.
