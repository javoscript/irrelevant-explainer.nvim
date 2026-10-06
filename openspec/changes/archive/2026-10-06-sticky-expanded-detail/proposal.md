# Proposal

## Why

Scrolling code can carry an expanded explanation completely out of the visible pane even though it remains selected. Keep the expanded reading area visible with edge-sticky placement, without losing the existing behavior where scrolling an explanation also scrolls its code.

## What Changes

- Keep expanded detail aligned with its selected summary while space permits; clamp its placement inside the explanation viewport when code-driven scrolling would take it past the top or bottom edge.
- Keep a short card fully visible and a long card's reading area available below the persistent header, with all prose reachable through native scrolling.
- Preserve explanation-driven paired scrolling, including while pinned: the sources follow actual prose viewport movement by display-row distance within native limits.
- Account for inherited and per-window source `scrolloff`, including unequal diff margins, without margin corrections adding a second scroll or losing synchronized distance.
- Separate card placement from prose reading position. Code-driven pinning/unpinning must not reset the reading position, change the selected note, steal focus, or scroll sources a second time.
- Return to natural alignment when code scrolls back, retain dimmed neighboring context when space permits, and recompute placement on resize or source display-geometry changes.
- Deliberately revise the existing symmetric expanded-scrolling contract: source-driven movement may be clamped in the explanation pane, while explanation-driven reading still moves code.
- Retain current expansion, entry navigation, anchor-bounded cursor mapping, collapse destinations, range styling, and lifecycle behavior. No new AI calls, settings, mappings, or detail popups.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Add sticky expanded-card placement and distinguish source-driven placement from explanation-driven paired scrolling.

## Impact

- `lua/explainr/ui.lua`: Expanded layout, scroll-driver handling, geometry updates, synchronization guards, and cleanup.
- `tests/ui_test.lua`: Replace source-driven equal-scroll expectations with sticky bounds, retaining explanation-driven distance checks and cursor/collapse regressions.
- `tests/visual.lua` and the existing `tests/render.py` workflow: Render aligned, top-pinned, bottom-pinned, and long-detail reading states.
- `README.md`, `doc/explainr-ui.txt`, and `doc/explainr.txt`: Describe the directional scrolling contract.
- Integrate with the current persistent-header and prose-cursor behavior, and the in-flight `expand-from-anchor-range` change without rewriting its artifacts. No new dependency or result-format change.
