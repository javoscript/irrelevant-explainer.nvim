# Proposal

## Why

Function/class targeting adds parser and language-query dependencies without fitting the plugin's intended scope model. Explicit visual selection already lets users explain a function, class, or any other region while controlling the exact boundaries.

## What Changes

- **BREAKING**: Remove `function` and `class` from `ExplainrCode`, its completion, and the Lua API's supported scopes. Reject retired values with guidance to use `selection` or `file`; do not alias them or silently broaden the target.
- Keep exactly five explanation scopes: visual selection, code file, diff file, diff hunk, and whole review. Code and diff commands keep `file` as their default.
- Remove structural Tree-sitter collection and the shipped language-specific explanation queries. Preserve optional Markdown highlighting in the reader.
- Preserve exact visual-region capture, unsaved/unnamed source support, whole-buffer context, accumulated notes, Refresh/Cancel/Close, and existing diff behavior.
- Replace structural examples and test fixtures with explicit selections, retaining coverage for accumulation, refresh, cancellation, and source ownership. Document migration for existing user mappings.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `code-explanation`: Remove structural targeting and restrict the public code scope contract to file and selection, with explicit rejection and migration behavior.

## Impact

Implementation touches `lua/explainr/code.lua`, command completion in `init.lua`, structural-specific session behavior if present, `queries/{lua,python,javascript,typescript}/explainr.scm`, tests, README, and help. Existing user mappings invoking function/class will need to use a visual selection or file scope instead. No parser installation/removal or user configuration rewrite is performed.

Whole-review batching and persistent caching belong to `batch-whole-review-explanations`. This change can be implemented first and does not require that larger change or alter its generation protocol. Main specs remain untouched until normal sync/archive.
