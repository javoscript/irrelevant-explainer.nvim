# Proposal

## Why

An explanation can cover many source lines, but Enter/K currently opens it only from its summary row. Explicit collapse also restores a saved summary position, interrupting reading by moving both cursors away from the current source-aligned line.

## What Changes

- Allow Enter/K in the collapsed explanation pane to expand a note from any row covered by its original anchors, including rows before a relocated diff summary.
- Preserve direct selection of visible summaries and existing combined folded summaries. On rows without summaries, open the sole covering explanation; when a file overview and one local explanation overlap, open the local explanation automatically.
- When multiple local explanations cover a row without a summary, offer a chooser containing summaries and original range labels, with local explanations first and covering overviews last. Do not silently choose the shortest range.
- Keep detail beneath its existing summary when space permits and do not move source code merely to expand it. Enter/K remains collapse-only while detail is open.
- Change Enter/K and Esc/q collapse to retain the current source-aligned position rather than returning to the summary or invocation row. Preserve source viewports and explanation focus within native geometry limits, and derive collapsed highlighting from the destination row.
- Preserve existing entry navigation, comparison geometry, source-buffer contents, optional Markdown rendering, and request behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Add anchor-range expansion with explicit overlap resolution and replace saved-entry collapse with current-position collapse, including entry-navigation and focus contracts.

## Impact

- Selection, detail layout, explicit collapse, and synchronization in `lua/explainr/ui.lua`; regressions in `tests/ui_test.lua`; user documentation in `README.md`, `doc/explainr.txt`, and `doc/explainr-ui.txt`.
- Uses Neovim's existing `vim.ui.select` integration for ambiguity, with no required picker dependency, new mapping, configuration, schema change, or additional AI call.
- Revises existing spec scenarios and tests that require explicit collapse to restore the current entry's summary. Does not change collapse caused by leaving anchored context or result replacement.
- Coordinate collapse target resolution with the separately proposed `sync-expanded-prose-cursor` change; this change requires the same visual-row semantics at collapse but does not introduce continuous prose cursor synchronization. Leave `stabilize-explanation-header` planning and implementation untouched.
