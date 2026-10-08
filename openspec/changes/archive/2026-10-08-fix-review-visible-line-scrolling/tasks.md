# Tasks

## 1. Review-local screen-row scrolling

- [x] 1.1 Add a focused regression in `tests/ui_test.lua` using the real Review pane, uneven wrapped paragraphs, and settled screen positions. Verify that single Ctrl-e/Ctrl-y presses move one visible row, counted inputs cross a paragraph/blank-line boundary by the requested row count, and source views remain unchanged; confirm it fails on the current implementation with smoothscroll initially disabled.
- [x] 1.2 Update `lua/explainr/ui.lua` to capture the pane's prior smoothscroll value in Review's extra saved options and enable it locally before restoring the Review view. Verify the scrolling regression passes without new mappings or changes to shared base options.
- [x] 1.3 Extend existing Review lifecycle coverage for initially disabled and enabled smoothscroll, unchanged source/global settings, and a Review-to-File-to-Review round trip with a clipped first paragraph. Verify File restores its prior setting and Review retains the complete saved view and subsequent one-row scrolling.
- [x] 1.4 Update the Review sections of `README.md` and `doc/explainr.txt` to explain visible-row Ctrl-e/Ctrl-y scrolling and count support. Verify the wording distinguishes Review from source-linked File scrolling and introduces no configuration requirement.

## 2. Integration verification

- [x] 2.1 Run targeted UI tests with `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`, then the full suite without EXPLAINR_TEST. Verify all checks pass and report any unrelated pre-existing failures separately.
- [x] 2.2 Exercise native start/end limits and idle/busy retained Review narratives at narrow and wide pane sizes, including a clipped wrapped first row. Verify row deltas, unchanged narrative text and source views, and stable reading position through loading updates; render and inspect captures of the affected idle/busy continuation states for gutter and wrapping regressions.
- [x] 2.3 Run `openspec validate fix-review-visible-line-scrolling --strict` and inspect the final diff. Verify it matches the delta contract and leaves unrelated work untouched.
