# Proposal

## Why

Scrolling an expanded explanation with Ctrl-e/Ctrl-y can leave the source cursor on a different line from the reader's current source-aligned target, especially at a sticky edge or inside a source scrolloff margin. Viewport movement already works, but its temporary cursor adjustments and final target selection are not completed as one reading action.

## What Changes

- Complete explanation-driven expanded scrolling with source cursor selection against the final reader/source geometry, including sticky-edge scrolling that leaves the Markdown cursor unchanged.
- Preserve the existing display-row scroll distance, native buffer limits, exact context targets, and visible-anchor bounds for prose selection.
- Keep source-driven scrolling, initialization, entry navigation, and geometry-only updates from applying the inactive reader's cursor to code.
- Preserve post-scroll source views, focus, diff bindings, and original local/global scrolloff settings; repeated editor events must not replay movement.
- Add regression assertions for final cursor targets as well as viewport deltas, and document the post-scroll selection behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Extend expanded visual-row synchronization to completed explanation-driven scrolls, not only detected prose cursor movement, while preserving context targeting and native source ownership.

## Impact

- Implementation: expanded scrolling and synchronization in `lua/explainr/ui.lua`, reusing `detail_target()` and `select_source()` rather than introducing another navigation controller.
- Verification: `tests/ui_test.lua` and representative rendered states through the existing `tests/visual.lua` / `tests/render.py` workflow.
- Documentation: the expanded navigation sections of `README.md` and `doc/explainr-ui.txt`.
- No new dependencies, configuration options, public APIs, source-buffer edits, or changes to collapsed overview behavior. The unrelated `runtime-auto-explain-toggle` change remains outside this scope.
