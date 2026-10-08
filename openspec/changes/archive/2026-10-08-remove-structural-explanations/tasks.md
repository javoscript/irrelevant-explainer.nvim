# Tasks

## 1. Restrict code targeting without changing selection behavior

- [x] 1.1 Restrict `code.lua` collection to file/selection, remove structural resolution, and simplify the narrow-target branch; replace structural collection tests with retired-scope rejection tests and verify existing exact character/line/block, multibyte, virtual, empty, unsaved and unnamed selection cases still pass without parsers.
- [x] 1.2 Update `ExplainrCode` completion and command/Lua validation, retaining file as the default and actionable function/class migration errors; test both entrypoints, no agent invocation or retired-scope cache lookup, fresh-note preservation, and unchanged ExplainrDiff file/hunk/review completion.
- [x] 1.3 Delete the four language-specific `explainr.scm` targeting queries and structural-only test setup; verify no source-target query lookup remains and optional Markdown highlighting/tests are untouched.
- [x] 1.4 Update README and `doc/explainr.txt` scope lists, parser requirements, examples and mappings; include old-command migration guidance and verify examples use only file/selection for code and file/hunk/review for diff without claiming Markdown highlighting was removed.

## 2. Preserve the reader lifecycle and verify compatibility

- [x] 2.1 Translate structural requests used as session/prompt fixtures into explicit visual descriptors; verify distinct overlapping batches coexist, repeat/Refresh replaces only the same target, Refresh after cursor movement retains the region, and cancellation/failure/stale output preserve the existing acceptance rules.
- [x] 2.2 Run the complete offline suite with `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`; verify code collection, commands, source-pane ownership, reader behavior, diff scopes and generic agent execution pass together without new parser requirements.
- [x] 2.3 Audit runtime/help/examples for remaining supported function/class scope claims and run `openspec validate remove-structural-explanations --strict`; verify remaining mentions are rejection tests, migration guidance or ordinary code examples, not advertised targeting support.

## Workflow follow-up

- During a separately requested sync/archive, reconcile the main code spec's historical Tree-sitter Decisions paragraph with the removed structural requirement. Do not alter archived changes.
