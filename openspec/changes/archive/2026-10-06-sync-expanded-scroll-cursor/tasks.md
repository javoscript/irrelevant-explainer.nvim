# Tasks

## 1. Complete expanded reading synchronization

- [x] 1.1 Add failing UI regressions using real Ctrl-e/Ctrl-y input for top-pinned prose with an unchanged reader cursor and source scrolloff normalization; verify independent expected cursor lines (including topline 69 / cursor 72 with scrolloff 0), correct viewport deltas, and failures on the current implementation using `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`.
- [x] 1.2 Update the shared expanded `scroll()` / `sync()` flow in `lua/explainr/ui.lua` to identify effective reading actions before overwriting snapshots, finish scrolling/placement, resolve the final target through existing helpers, and save settled views under the guard; verify the regressions pass without extra viewport movement or duplicated selection.
- [x] 1.3 Extend focused regressions for inherited/local scrolloff 0, 5, and viewport-centering values, both sticky edges and release, counted movement into anchored continuation, repeated cursor/scroll/idle/redraw events, and current-position collapse; verify final cursor targets, post-scroll views, local `-1` inheritance, focus, and detail identity together in the targeted UI suite.
- [x] 1.4 Preserve source-driven native cursor ownership, untouched opening/n/p initialization, geometry-only reflow, outside-context collapse, no-visible-anchor fallback, and true BOF/EOF no-ops; verify existing checks remain green and add focused assertions only where these exclusions are not already exercised by the updated reading path.
- [x] 1.5 Update the existing expanded-navigation sections of `README.md` and `doc/explainr-ui.txt` to describe final post-scroll visual-row selection and its context/anchor bounds; verify the wording preserves source-driven sticky behavior and does not imply Markdown-line-number mapping or permanent scrolloff changes.

## 2. Verify geometry and native diff integration

- [x] 2.1 Extend existing wrapped/folded and deletion-filler fixtures with final cursor assertions after explanation-driven scrolling, including unequal old/new scrolloff margins and a disjoint-anchor tie; verify known fixture targets independently of `detail_target()`, unchanged fold/wrap state, native comparison cursor positions, preserved viewport deltas, and existing large-file scrolling bounds in the UI suite.
- [x] 2.2 Add or extend affected states in `tests/visual.lua`, then capture them through `tests/render.py` under locally excluded `.amp/in/artifacts/`; inspect top-pinned Ctrl-y, a bottom-edge scrolloff case, and a diff continuation/deletion case for the expected cursor/source alignment, preserving the reader card and focus. Exercise optional Markdown rendering when available and report any environment limitation.

## 3. Integration checks

- [x] 3.1 Run the targeted UI suite and `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` for full editor coverage; verify all results honestly and confirm existing collapsed navigation, session ownership, and cleanup behavior remain unchanged.
- [x] 3.2 Run `openspec validate sync-expanded-scroll-cursor --strict`, inspect the final implementation diff against the delta scenarios, and verify no unrelated runtime-toggle work or source options/buffers were changed; report verification results and link an inspected representative visual artifact.

## Verification outcome

- Native UI suite: 140 passed, 0 failed. Optional Markdown renderer UI suite: 142 passed, 0 failed.
- Full current-worktree suite: 243 passed, 1 failed. The isolated real Diffview subprocess hits its 60-second timeout while running the concurrent runtime-toggle tests; that work was left untouched. The pre-existing Diffview test file from HEAD, run against the current implementation, passes all 10 tests, including session closure and comparison navigation.
- Strict OpenSpec validation and `git diff --check` pass. Three rendered states (top-pinned scrolling, bottom-edge scrolling, deletion-side pin release) were captured and inspected both natively and with the installed Markdown renderer under `.amp/in/artifacts/scroll-cursor-native/` and `.amp/in/artifacts/scroll-cursor-rendered/`.
