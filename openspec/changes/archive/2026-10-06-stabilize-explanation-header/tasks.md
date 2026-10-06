# Tasks

## 1. Persistent matched header lifecycle

- [x] 1.1 Generalize source-header reservation in `lua/explainr/ui.lua` to the pane's lifetime and make overview/detail headers always use the matched winbar; remove content-status and no-winbar count fallbacks while preserving unrelated decorations. Update `tests/ui_test.lua` expectations and verify pending-to-ready transitions with and without overview notes keep the same content screen rows and buffer line counts, including wrapped/folded source and diff filler.
- [x] 1.2 Cover owned-source reconciliation and placeholder cleanup in `tests/ui_test.lua`: mixed existing/blank diff headers, source switching, cleared results, stale/failure/cancelled states, user header replacements, and pane close. Verify only unchanged owned placeholders are restored, all paired content remains aligned, and local/global statuslines remain untouched.
- [x] 1.3 Update header-position and lifecycle descriptions in `README.md`, `doc/explainr-ui.txt`, and `doc/explainr.txt`; verify they describe reservation from opening, retention until ownership loss/close, and no content-overlay fallback.

## 2. Stable semantic header styling

- [x] 2.1 Add default-only `ExplainrTitle` styling and segment-based native winbar formatting for overview and compact expanded headers, reusing intent marker groups and `ExplainrMetadata`. Add evaluated-highlight regressions with distinct custom colors; verify pending/ready/failed/stale/cancelled and expanded states share the same palette, each D/~/? matches its item marker, and descriptions/separators reset to muted styling.
- [x] 2.2 Preserve display-cell width budgeting, count-first prioritization, compact legend variants, and literal-percent escaping before winbar serialization. Update header-reading test helpers to evaluate displayed text, and verify narrow/wide headers, multibyte status text, `%` literals, counts through entry navigation/expansion, and spinner ticks that do not modify buffers or invoke full renders.
- [x] 2.3 Document title/muted/intent-symbol colors and the title highlight override in `README.md` and `doc/explainr-ui.txt`; verify the named groups and narrow-width behavior match the implementation.

## 3. Integrated verification

- [x] 3.1 Run `EXPLAINR_TEST=tests/ui_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`, then the full offline suite without `EXPLAINR_TEST`; verify header changes preserve source geometry, focus, loading animation, statusline ownership, and expanded navigation, including combined behavior if the separate prose-cursor change has landed.
- [x] 3.2 Render and capture representative pending, ready, and expanded panes, including a narrow pane and two-sided diff; inspect the captures to verify stable header placement, accent title, muted text, intent-marker colors, and aligned source rows. Store review captures under `.amp/in/artifacts/` after ensuring `/.amp/in/` is locally excluded, and record any rendering limitation instead of treating structural checks as visual verification.
