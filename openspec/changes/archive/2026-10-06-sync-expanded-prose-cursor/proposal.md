# Proposal

## Why

Moving through an expanded explanation leaves the source cursor at its previous line even when the prose cursor sits beside another line inside the explanation's anchors. The current implementation and spec separate prose movement from source navigation too broadly: avoiding Markdown-line mapping should not prevent visual-row synchronization.

## What Changes

- Synchronize explanation-driven cursor movement through expanded summaries, metadata and prose to the source display row beside the cursor, even without viewport scrolling.
- Resolve displayed rows using source geometry, including wrapping, closed folds and diff filler, rather than treating Markdown buffer line numbers as source line numbers.
- Limit prose-driven cursor targets to the expanded explanation's anchored ranges; keep longer prose freely readable without collapsing or selecting unrelated code. Preserve native viewport scrolling when anchors are off-screen.
- Preserve existing mapped continuation/context navigation, collapse-at-destination behavior, explicit entry navigation, focus ownership and paired viewport scrolling.
- Update the expanded-navigation contract and user documentation, with regressions covering anchored prose movement and boundary/geometry cases.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Refine free expanded cursor and scrolling to allow anchor-bounded visual-row synchronization through prose while continuing to prohibit Markdown-line-number mapping.

## Impact

- Implementation is scoped to expanded synchronization and layout metadata in `lua/explainr/ui.lua`, reusing existing source projection and comparison-coordinate resolution.
- Regression coverage belongs in `tests/ui_test.lua`; behavior documentation belongs in `README.md` and `doc/explainr.txt`.
- No new dependencies, configuration, mappings, external-agent calls, source-buffer edits or changes to Diffview comparison membership.
- The existing long-paragraph scenario must change: prose cursor movement may select another anchored source line by its display position, but must not infer a semantic relationship between paragraph text and code.
