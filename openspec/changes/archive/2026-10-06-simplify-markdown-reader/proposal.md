# Proposal

## Why

Expanded explanations need predictable reading and source alignment more than decorative Markdown rendering. Renderer concealment and decorations complicate display geometry, while native buffer-line j/k independently skip wrapped screen rows; removing the renderer alone would not fix that navigation behavior.

## What Changes

- **BREAKING**: Remove Explainr's optional render-markdown.nvim integration from both overview and detail; installed renderer configuration no longer determines Explainr presentation.
- Use the `explainr` filetype for both buffers, retaining optional Markdown Tree-sitter highlighting and existing semantic styling without concealing Markdown markers or adding renderer layout decorations.
- Preserve Markdown explanation content, native detail wrapping, focus tint, gutters, metadata, source ranges, and expansion controls. Missing parsers remain nonfatal.
- **BREAKING**: Make normal-mode expanded j/k, including counts, move by displayed row rather than buffer line. Preserve the special upward-scroll action at the top-edge summary, narrowed to its first displayed segment.
- Preserve collapsed navigation, source synchronization, sticky placement, current-position collapse, and the separate in-progress post-scroll cursor correction.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Replace optional renderer support with renderer-free Markdown highlighting and specify display-row j/k navigation in expanded detail.

## Impact

- Implementation owner: `lua/explainr/ui.lua`, including renderer lifecycle hooks, detail buffer setup, and expanded key mappings.
- Verification: `tests/ui_test.lua` and existing `tests/visual.lua` / `tests/render.py` captures, with optional parser and installed-renderer isolation coverage.
- Documentation: `README.md` and `doc/explainr-ui.txt` must describe visible Markdown markers, optional syntax support, and expanded movement semantics.
- No new dependency, public configuration, parser installation, model-output change, source-buffer edit, or renderer setup change. No plain-text conversion or Markdown injections into source buffers.
- Coordinate with `sync-expanded-scroll-cursor`, which owns final post-scroll source selection in the same UI module. This change does not replace or revert that work; `runtime-auto-explain-toggle` remains unrelated.
