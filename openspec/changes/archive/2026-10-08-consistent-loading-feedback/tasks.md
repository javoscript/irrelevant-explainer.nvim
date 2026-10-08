# Tasks

## 1. Busy headers and saved-result ownership

- [x] 1.1 Add failing UI/session regressions for Checking saved explanations, Checking saved review, cache lookup, and result-context validation; verify animation starts without fake inference requests and cached answers still wait for freshness before installation.
- [x] 1.2 Share busy classification and expose selected restoration/owned background activity through the existing session renderer; verify delayed A-to-B restoration cannot decorate or install A in B and silent periodic checks do not leave an idle reader spinning.
- [x] 1.3 Keep header ticks active with focus and expanded detail, and reserve spinner width in compact File/Review headers; verify changing frames changes the rendered header at both sides of a width boundary without changing detail buffers, cursors, views, counts/Auto priorities, annotation percentages, statuslines, or undecorated status values.
- [x] 1.4 Document the focused-header and saved-check behavior in README.md and doc/explainr.txt; verify both describe checking as activity without implying a provider call or fabricated progress.

## 2. Continuous loading rails

- [x] 2.1 Add failing rendered-screen regressions for a Review paragraph wrapping onto at least four rows, intervening blank lines, a clipped first continuation, resize, and empty space below EOF; verify every eligible screen row has a rail rather than merely asserting one extmark per logical line.
- [x] 2.2 Replace Review sign glyphs with a fixed-width, buffer-safe native gutter and lightweight Review cursor/scroll/resize updates; verify continuous rail/tint coverage, unchanged wrapping and text changedticks, preserved reading/source positions, and blank safe rendering when gutter data is absent during transitions.
- [x] 2.3 Add restoration loading over the current File extent and retain existing matching request-range behavior; verify coherent replacement sources drive wraps/folds/filler, pre-coherence placeholders do not reuse old anchors, and background review/file work does not tint unrelated accepted content.
- [x] 2.4 Replace cursor-line omission with a steady rail across its logical/wrapped extent in File and Review; verify two frames keep that line's rail intensity equal while another eligible row and the header advance, and moving the cursor resumes the previous row without text/background flicker or content changes.
- [x] 2.5 Cover Ready, Failed, Cancelled, Stale, navigation, Review/File/detail switching, and closure in lifecycle tests; verify decoration/freeze cleanup, timer retirement when all work stops, rejected late callbacks, unchanged source/explorer options, and retained inference/cache ownership.
- [x] 2.6 Update loader documentation and visual fixtures for restoration, retained review checking, focused paragraphs, empty Review, and narrow/detail headers; verify descriptions match the steady cursor-line policy and fixtures use offline explanations without provider calls.

## 3. Integration and visual verification

- [x] 3.1 Run targeted UI, session, and Diffview tests followed by `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`; verify all checks pass and animation does not rewrite buffers, rebuild File/detail layouts, or perform whole-file geometry scans on ticks. Repeat on available supported Neovim 0.11/0.12 installations, documenting any unavailable version.
- [x] 3.2 Use tests/render.py to capture and inspect saved-file checking, retained review result-context checking, focused wrapped prose, clipped/empty Review, narrow headers, and expanded-detail background activity; verify continuous rails and visible spinners with stable layouts. Store review captures under locally excluded .amp/in/artifacts/ and include final inspected artifacts in the implementation summary.
- [x] 3.3 Validate the implementation against this change's delta scenarios and run `openspec validate consistent-loading-feedback --strict`; verify planning artifacts remain coherent with actual loading behavior and report any verification limitation before declaring implementation ready.

## Verification

- Neovim 0.12.5: UI 163/163, session 26/26, real Diffview child 27/27; full suite 328/328. Neovim 0.11 was not available on this runner.
- Strict OpenSpec validation and `git diff --check` passed. Captured and inspected all loading fixtures with `tests/render.py`, using the installed Fira Code Nerd Font for braille/arrow glyph coverage, under locally excluded `.amp/in/artifacts/`.
- No provider calls in visual fixtures; cache/freshness and delayed restoration assertions preserve inference ownership and result acceptance.
