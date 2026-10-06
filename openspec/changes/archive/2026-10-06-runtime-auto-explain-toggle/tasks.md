# Tasks

## 1. Runtime toggle and navigation lifecycle

- [x] 1.1 Add `toggle_auto_explain()` and `ExplainrToggleAutoExplain` in `lua/explainr/init.lua`, preserving unrelated configuration and returning/notifying the new mode; extend `tests/model_test.lua` with Lua/command round trips, custom agent/context preservation, setup reset semantics, and no-pane dependency laziness, and verify those tests pass.
- [x] 1.2 Add per-navigation eligibility in `lua/explainr/session.lua` at both automatic-request boundaries and revoke deferred eligibility on disabling without cancelling started or queued work; extend Diffview/session tests to verify enable-on-current-file issues zero calls, subsequent navigation issues one, disable-during-inference preserves completion, manual refresh/queued hunks still work, saved notes restore, and code mode stays manual.
- [x] 1.3 Cover delayed coherent buffers, failed saved-note validation, and background-tab activation across enabling/disabling, including off/on before deferred work finishes; verify no earlier navigation is revived and a fresh enabled navigation still requests exactly once under existing ownership/no-retry rules.
- [x] 1.4 Document the runtime command, Lua return value, informational notification, process-wide scope, subsequent-navigation behavior, and explicit Cancel semantics in README/help alongside `diff.auto_explain`; include a user-defined `<leader>ea` mapping and verify the documented command/API names and mapping against implementation without installing default mappings.

## 2. Live automatic-mode headers

- [x] 2.1 Propagate the live mode through the existing session registry to every owned diff pane and initialize new panes before snapshot collection completes; extend session tests to verify immediate cross-tab updates without switching focus, disturbing work/notes, or showing an indicator on code panes.
- [x] 2.2 Extend header-only updating in `lua/explainr/ui.lua` to cover overview and expanded detail, placing muted `Auto` after counts when enabled and omitting it otherwise; extend `tests/ui_test.lua` to verify all request states, snapshot-free pending/unexplained states, narrow-width priority, semantic styling, unchanged `pane.status`/`vim.b.explainr_status`, and untouched editor statuslines.
- [x] 2.3 Add expanded-reader preservation tests around both toggle directions; verify identical detail buffer and selected note, cursor/view positions, focus, and content before/after header refresh, with no expansion/collapse, inference, or full content replacement.
- [x] 2.4 Document `Auto` as an enabled navigation mode rather than a running-request marker in README and `doc/explainr-ui.txt`; verify overview/detail wording matches the delivered indicator and explicitly distinguishes Explainr's winbar from the user's statusline.
- [x] 2.5 Extend the existing actual-screen fixtures only as needed and use `tests/render.py` to capture enabled diff overview, expanded detail, a narrow header, and a disabled comparison; save artifacts under locally excluded `.amp/in/artifacts/`, inspect them for count/indicator visibility, preserved alignment, and unchanged editor statusline, and retain a representative inspected capture for review.

## 3. Integrated verification

- [x] 3.1 Run `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` with the supported Diffview runtime available; verify the full offline suite passes and the feature's Diffview tests actually execute rather than skip, reporting any environment limitations honestly.
- [x] 3.2 Run `openspec validate runtime-auto-explain-toggle --strict` and review the final diff against both delta specs; verify all scenarios have test or inspected-render coverage and changes remain limited to the toggle, navigation gating, headers, their documentation, and fixtures.
