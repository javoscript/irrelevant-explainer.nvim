# Proposal

## Why

Expanded explanations can visibly scroll and snap back at the top edge, and Ctrl-y can appear stuck when moving the card farther down would clip its prose. Reader navigation should settle without a corrective flash and allow an intentional exit into surrounding code context rather than treating card placement as a file boundary.

## What Changes

- Resolve expanded Ctrl-e/Ctrl-y scrolling and final placement before presenting a frame, avoiding an intermediate scroll followed by a visible snap-back.
- When further reader Ctrl-y is blocked solely by the bottom placement limit of a fitting card, move to the source-backed display row immediately above that card. Collapse at that destination only if it lies outside the selected anchors.
- Reaching an edge alone does not collapse detail. Source-driven scrolling retains sticky placement, and genuine native limits remain no-ops.
- Preserve long-prose reading, counts, wrap/fold/filler coordinates, source synchronization, focus, and scrolloff settings. Add event-sequence and actual-screen regressions for both reported cases.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Refine free expanded scrolling to distinguish a card-placement limit from a native file limit, define the Ctrl-y context escape, and require settled reader frames without corrective scroll flashes.

## Impact

- Implementation owner: `lua/explainr/ui.lua`, especially `pane:scroll()`, `pane:place_detail()`, outside-context collapse in `pane:sync()`, and deferred scroll/idle reconciliation.
- Verification: `tests/ui_test.lua`, with actual Neovim UI-grid coverage through `tests/visual.lua` and `tests/render.py` where needed.
- User documentation: scrolling guidance in `README.md` and `doc/explainr.txt`.
- No new dependencies, public configuration, AI requests, source-buffer edits, or changes to source-window key mappings. This proposal creates planning artifacts only.
