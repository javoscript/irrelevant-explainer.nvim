# Tasks

## 1. Source-driven sticky placement

- [x] 1.1 Extend expanded layout in `lua/explainr/ui.lua` to track unclamped summary position separately from card/prose height and continuation extent, retaining the same detail buffer; add tests where a short card covers a long source range and verify its bounds use card height rather than anchored blank rows.
- [x] 1.2 Route source-driven scrolling through top/bottom placement clamping instead of prose-scroll replay, preserving source views, selection, focus and reading state; verify screen-row assertions for interior alignment, each edge, one row either side of each boundary, reverse-scroll release, and the reproduced line-40/25-row-scroll case.
- [x] 1.3 Refresh navigable dimmed context, source-coordinate mappings, rails and tint when the card moves; verify neighboring notes remain reachable, intentional outside-context movement still collapses at its destination, and placement alone neither collapses nor maps the inactive prose cursor to code.
- [x] 1.4 Update `doc/explainr-ui.txt` to describe source-driven sticky placement and its directional exception to equal viewport movement; verify the described top/bottom and reverse-scroll behavior against the new UI tests.

## 2. Explanation-driven reading and event ownership

- [x] 2.1 Preserve native explanation-driven scrolling while pinned and synchronize sources using actual display-row viewport deltas; split the existing symmetric expanded-scroll assertions by driver and verify counted Ctrl-e/Ctrl-y, page/half-page scrolling, zz/zt/zb, and cursor-induced scrolling with asymmetric wraps, folds, diff filler and native EOF limits.
- [x] 2.2 Preserve logical paragraph position, cursor column and wrapped segment across source-driven pin/unpin, retaining a viewport-sized reading area for long detail; add a long multi-paragraph regression that reads into a later wrapped segment, scrolls code, then resumes prose scrolling and verifies every paragraph stays reachable and code still follows.
- [x] 2.3 Refresh synchronization snapshots and initialization/reading guards after final layout, rejecting paired-source follow-up events as new drivers; verify repeated CursorMoved/WinScrolled/SafeState events cause no duplicate scroll, snap-back or source-view change, and update `README.md` with the agreed code-follows-explanation rule.
- [x] 2.4 Fix scrolloff-related desynchronization using actual source geometry and native counterpart validation before paired scrolling; verify inherited global margins 5/999, unequal diff margins 5/9, counted/half-page and zz/zt/zb actions, active-context selection, repeated redraw/events and preserved global/local option values.

## 3. Geometry, navigation and lifecycle integration

- [x] 3.1 Route expanded resize, source fold/side changes and diff-filler updates through sticky layout recomputation without overview buffer swaps; verify tall-to-short and short-to-tall reflow, mixed source winbars, old-only deletion anchors, and persistent header/source-option preservation in `tests/ui_test.lua`.
- [x] 3.2 Reset sticky metadata on n/p/N initialization and clear it on back/set/close and diff file replacement; verify current-position collapse after pinning, untouched initialization collapse, disjoint/no-visible-anchor cursor mapping, buffer reuse, file-switch cleanup and paired-window closure, and update `doc/explainr.txt` with reading-position and lifecycle guarantees.
- [x] 3.3 Add representative aligned, top-pinned, bottom-pinned, long-detail reading and resized states in `tests/visual.lua`; capture them with the existing `tests/render.py` workflow under `.amp/in/artifacts/` after ensuring the local exclude rule, inspect the actual screenshots for card/body visibility, header clearance, gutter/tint continuity and neighboring context, and exercise optional Markdown rendering when available.

## 4. Combined verification

- [x] 4.1 Run `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` and the full `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` suite against the combined worktree; verify persistent headers, prose cursor synchronization and range-based expansion/current-position collapse remain correct alongside sticky behavior, reporting any unavailable optional integration checks.
- [x] 4.2 Run `openspec validate sticky-expanded-detail --strict` and review the implementation against every delta scenario, including rendered pinning states; verify the proposal, design, tasks and documentation agree on code-driven placement versus explanation-driven paired scrolling before marking the change ready for archive.
