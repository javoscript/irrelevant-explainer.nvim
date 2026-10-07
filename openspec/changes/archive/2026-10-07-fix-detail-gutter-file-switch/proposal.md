# Proposal

## Why

Switching Diffview files after reading expanded explanations can flood Neovim with `E121: Undefined variable: b:explainr_detail_active` and `E116: Invalid arguments for function get`. The detail gutter assumes buffer-local data exists whenever its window-local expression runs; an isolated buffer-replacement reproduction confirms this failure, though the exact transition in the reported sequence remains unconfirmed.

## What Changes

- Make detail-gutter evaluation safe when detail data is absent, while retaining active rails and existing padding when it is present.
- Keep the detail gutter scoped to its reader and restore the appropriate gutter on collapse, file replacement, and cleanup; correct option leakage demonstrated by targeted reproductions.
- Cover switching through the Diffview explorer both with detail expanded and after explicit collapse, with auto-explain enabled through the runtime toggle and with it disabled.
- Preserve navigation, saved-note restoration, request cancellation, automatic request counts, and source-window settings.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Require safe detail-gutter evaluation through buffer transitions and prevent detail-gutter options from leaking into overview, source, explorer, or surviving editor windows.

## Impact

- Primary implementation owner: `lua/explainr/ui.lua`, including detail creation, gutter decoration, collapse, and cleanup.
- Regression coverage: `tests/ui_test.lua` and `tests/diffview_test.lua`, using the existing offline Diffview fixture and stubbed agent responses.
- `lua/explainr/session.lua` follow/retention behavior is an integration boundary, not a planned redesign.
- No new dependencies, commands, configuration, inference behavior, or intentional visual redesign.
