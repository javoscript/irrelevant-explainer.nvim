# Design

## Context

See proposal.md for motivation. `code.lua` currently validates four scopes, resolves function/class through `structural()` and shipped Tree-sitter queries, then turns the chosen node into a selection descriptor. File and visual collection already work independently of a parser. `init.lua` advertises all four code scopes, while `session.lua` owns generic code accumulation and Refresh. Session tests use structural requests both to test targeting and as convenient narrow-target fixtures.

The main code spec explicitly requires structural scopes and mentions them in context, overview, accumulation, and command/refresh scenarios. All those blocks need a coherent delta. Optional Markdown parsing belongs to reader highlighting, not source targeting.

## Goals / Non-Goals

**Goals:** Simplify the existing collection path, preserve exact selection descriptors and code-reader lifecycle, and make the API break explicit without changing remaining scope behavior.

**Non-Goals:** New text objects, automatic selection expansion, compatibility aliases, parser management, diff changes, cache implementation, protocol changes or UI layout changes.

## Decisions

### Validate only file and selection, then simplify collection

Restrict the shared code collection boundary to file/selection so direct collection and command/Lua callers agree. Retired values receive a specific migration hint and never reach cache lookup or inference. Change command completion to match. Remove `structural()` and its branch; the narrower path uses only the supplied or captured visual descriptor. Keep region handling, empty-selection rejection, full-buffer context, freshness guards and accepted-note retention intact.

An alias to selection is unsafe because it would depend on unrelated old Visual marks; an alias to file silently broadens user intent. Keeping a disabled structural resolver adds maintenance for a removed feature. Rejecting the old names is smaller and predictable.

### Remove source-target queries, not reader highlighting

Delete only the explanation query files for Lua, Python, JavaScript and TypeScript and structural-specific test setup/assertions. Do not remove the user's installed parsers, unrelated highlight queries or optional Markdown highlighting. Do not add a new parser dependency for file/selection.

### Preserve lifecycle tests with explicit regions

Replace function/class requests used merely as fixtures in `tests/session_test.lua` and related suites with distinct explicit visual descriptors. Preserve the underlying assertions for overlapping batches, replacement, refresh after cursor movement, cancellation, source ownership and stale results. Replace structural-resolution tests with unsupported-scope/no-agent tests; keep selection edge cases and unsaved/unnamed tests. Use command completion and public Lua calls in acceptance coverage, not only internal collection.

### Keep the two OpenSpec changes independent

This delta modifies/removes existing code requirements; `batch-whole-review-explanations` adds the separate cross-session code reuse requirement. Applying scope removal first simplifies subsequent cache integration, but neither change requires the other to be archived. Cache lookup must still validate supported scopes before considering stored entries. There is no migration of function/class cached answers into selection answers.

## Risks / Trade-offs

- Existing mappings break → actionable retired-scope errors and README/help migration examples; no automatic user configuration edits.
- Removing fixtures could weaken unrelated coverage → translate lifecycle fixtures rather than deleting their tests, and compare assertion intent before/after.
- Broad Tree-sitter cleanup could remove reader highlighting → limit deletion to source-target query files and verify Markdown tests still pass.
- Stored old targets could bypass the new scope contract → validate scopes before any reuse when integrating the cache change.

## Migration Plan

Update collection, command completion, tests and docs together. Replace example function/class mappings with an explicit visual-mode selection mapping or file request. State that users can select a function/class themselves, but Explainr no longer discovers those boundaries. Run the complete offline headless suite, with targeted command/API and selection-refresh tests. No visual redesign is planned; existing UI assertions verify retained reader behavior.

When syncing/archiving, reconcile the main code spec's non-normative Decisions paragraph about Tree-sitter targeting with the removed requirement; do not leave historical guidance presented as current behavior. Planning does not edit main specs or archived history. Rollback restores the prior plugin implementation and query files; no source, database or external-service migration is involved.
