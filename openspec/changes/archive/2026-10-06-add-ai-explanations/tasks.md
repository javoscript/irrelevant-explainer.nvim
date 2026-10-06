# Tasks

## 1. Plugin foundation and explanation contract

- [x] 1.1 Establish a minimal Lua plugin entrypoint, setup validation, and an offline headless Neovim test harness; verify loading works on the documented Neovim baseline without Diffview or an AI executable installed.
- [x] 1.2 Define snapshot/target ranges and the versioned note contract from design decision 4; verify independent fixtures cover buffer, old/new paired anchors, renamed paths, valid empty notes, and rejection of malformed or out-of-target notes and absent evidence.
- [x] 1.3 Document the compatibility baseline, setup shape, and test command alongside the foundation; verify the documented command runs the fixture suite without provider credentials.

## 2. Prove aligned rendering with fixed explanations

- [x] 2.1 Open the right-hand read-only scratch pane and project sparse fixed notes onto source display rows; verify asserted screen coordinates for blank intervening rows, Unicode-width truncation, resize, winbar differences, and top/bottom viewport boundaries without changing source text/options.
- [x] 2.2 Extend projection to wrapped lines, partially scrolled wraps, closed folds, unequal old/new diff ranges, and deletion-only filler rows using native diff fixtures; verify hand-authored expected row mappings rather than expectations derived from the projection implementation.
- [x] 2.3 Synchronize source-to-note scrolling and note-pane scroll commands back to the source with recursion guards; verify page/mouse scrolling keeps alignment and preserves the original two-way diff synchronization and membership.
- [x] 2.4 Add floating detail, grouped folded/shared-row notes, and pending/failed/stale status display; verify detail opens from existing data with zero process invocations and closes without shifting either pane.
- [x] 2.5 Add source/window closure and explicit pane-disable cleanup; verify no owned windows, buffers, handlers, or source-option changes remain after close/reopen cycles and unrelated windows remain intact.
- [x] 2.6 Document pane navigation and the aligned-versus-expanded interaction; render and inspect captures for sparse notes, narrow truncation, wraps/folds, deletion filler, and open detail to verify the documented layout before adding live AI.

## 3. Code scopes and snapshot-bound prompts

- [x] 3.1 Collect immutable current-buffer file and characterwise/linewise/blockwise selection targets with full-file context; verify unsaved and unnamed buffers, reversed selections, multibyte/tab column boundaries, and empty-selection rejection against independently chosen expected spans.
- [x] 3.2 Add Tree-sitter enclosing-function/class scope queries for the initial tested grammar set; verify nested functions and class methods select the smallest correct structure, and missing parsers/queries/nodes report errors without automatic scope broadening.
- [x] 3.3 Build code prompts that separate instructions, untrusted context, target, and the structured output contract; verify fixtures include imports outside the target, retain source positions, request short/full explanations, and avoid asserting unavailable dependency behavior.
- [x] 3.4 Bind code results to generation/content identities and add explicit refresh behavior; verify edits before and after completion reject late output or mark notes stale, without automatically issuing another AI call.
- [x] 3.5 Document code commands, visual invocation, supported grammar scopes, and parser requirements; verify documented invocations select the expected file/function/class/selection in fixture buffers.

## 4. External-agent execution

- [x] 4.1 Run user-configured argv asynchronously with stdin/EOF and separate stdout/stderr; verify fake executables receive quotes, newlines, Unicode, and shell metacharacters unchanged, while the editor remains responsive and launch failures are surfaced.
- [x] 4.2 Implement the OpenCode completed-message decoder, Codex completion-aware decoder, plain-output mode, and custom decoder callback; verify version-labeled fixture streams with split/coalesced chunks, multiple text parts, schema-shaped progress, reasoning/tool events, empty output, and errors after partial text.
- [x] 4.3 Add timeout, cancellation, and replacement guards around owned execution; verify a delayed fake command cannot update closed or newer panes, nonzero/failure/incomplete results are rejected, and no automatic provider fallback occurs.
- [x] 4.4 Enforce the complete serialized UTF-8 prompt-byte budget before launching commands; verify exact-limit and one-byte-over cases, multibyte input, and an instructions/output-contract overhead case in which source alone would fit.
- [x] 4.5 Connect validated command results to code-mode rendering; verify an end-to-end fake-agent invocation produces the expected sparse notes, immediately available detail, and actionable validation errors instead of guessed anchors.
- [x] 4.6 Document OpenCode/Codex/plain/custom command examples, tested output versions, restricted-agent configuration, byte-budget semantics, retention/billing ownership, and local-versus-attached cancellation limits; verify example command shapes against the supported CLI contracts without initiating paid inference or login.

## 5. Diffview comparison context and focused explanations

- [x] 5.1 Implement the optional Diffview compatibility adapter using documented display/lifecycle hooks and isolated private comparison metadata; verify a recorded supported Diffview revision, coalesced asynchronous pane loading, live role/window IDs, and clear rejection of merge or ambiguous scopes without requiring Diffview in code mode.
- [x] 5.2 Collect complete manifest and versioned text/patches for the selected coherent comparison, including working/index overlays; verify disposable Git fixtures with revision pairs different from the default working-tree diff, unrelated local edits, unsaved buffers, staged-versus-working scope labels, additions, deletions, empty files, renames, and binary markers.
- [x] 5.3 Assemble whole-review context plus complete changed decision/document versions and the focused file/hunk; verify a multi-file fixture includes policy, tests, an OpenSpec requirement, a non-OpenSpec ADR with unchanged rationale, and explicit old/new identities while notes remain restricted to the target.
- [x] 5.4 Add diff-specific prompts for observable effects, documented/inferred/unknown intent, evidence, and decision/code mismatches; verify prompt fixtures for owner-only cancellation, code that still permits editors, absent rationale, and repository text containing hostile instructions.
- [x] 5.5 Map validated old/new notes, including deletion-only and old59/new62 replacements, into the established projection/detail UI; verify real Diffview fixture coordinates and evidence display without adding prose to diff computation or altering source options.
- [x] 5.6 Add consistent mutable-snapshot checks, review/target fingerprints, in-memory context/result reuse, and Diffview file/layout/revision/closure invalidation; verify nonfocused document edits, filesystem/index changes, rapid file switches, and late command completion cannot install stale notes or silently reuse obsolete review context.
- [x] 5.7 Document whole-comparison scope, changed-document inclusion, unsupported layouts/binary targets, explicit refresh, and no-truncation budget errors; render and inspect an MR-style fixture with cross-file business evidence, deleted lines, and open detail to verify the documented interaction.

## 6. Combined acceptance checks

- [x] 6.1 Run the complete offline headless, fake-process, parser-query, and supported-Diffview integration suites; verify every capability scenario has exercised acceptance coverage and the suite requires no provider credentials or production writes.
- [x] 6.2 Exercise full code/diff flows with fixed-size rendered captures, including scroll from each pane, refresh failure, edit invalidation, resize, file switching, detail expansion, and teardown; inspect the captures and confirm no repository/source modifications or lingering owned execution/windows remain.
- [x] 6.3 Cross-check implementation, help/config examples, and these OpenSpec artifacts; verify commands and examples match the delivered API, supported versions/limitations are explicit, and OpenSpec validation passes before proposing archive or release actions.
