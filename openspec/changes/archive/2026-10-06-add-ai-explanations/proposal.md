# Proposal

## Why

Reading unfamiliar code and reviewing multi-file changes requires understanding both local behavior and the intent behind it. Explainr.nvim will bring AI explanations alongside the code, connecting changed lines to requirements, design decisions, and tests elsewhere in the same review without requiring users to manage a separate chat.

## What Changes

- Introduce code explanation for whole files, enclosing functions/classes using Tree-sitter, and visual selections.
- Introduce diff explanation in Diffview for two-way text comparisons, using the entire selected comparison as context while producing notes for the focused file or hunk.
- Consider business and technical decisions in changed documentation, including but not limited to OpenSpec artifacts; distinguish documented intent, inferred intent, and implementation mismatches.
- Display concise notes in a right-hand buffer aligned with source display rows. Expand existing notes into floating detail, and synchronize scrolling without altering the source or joining the explanation window to a diff comparison.
- Delegate AI execution, authentication, model selection, and billing to user-configured external commands. Decode supported command output and validate structured notes before displaying them.
- Reject stale results and report failed commands, invalid output, unsupported comparisons, and context-budget overflow instead of displaying misleading explanations.
- Keep the first version focused on explanation: no code editing, native provider login, inline/ghost-text renderer, continuous narrative pane, CodeDiff integration, or merge-conflict explanation.

## Capabilities

### New Capabilities

- `code-explanation`: Scope selection, immutable code/context snapshots, and behavior-focused explanations for source buffers.
- `diff-explanation`: Whole-comparison review context, focused old/new anchors, and explanations grounded in cross-file decisions and evidence.
- `aligned-explanation-ui`: Row-aligned notes, scrolling, floating detail, and paired-window lifecycle for both modes.
- `external-agent-execution`: Configurable noninteractive commands, output decoding, validated explanation results, and explicit failure handling.

### Modified Capabilities

None. The project currently has no durable capability specs or implementation.

## Impact

- Establishes a Lua Neovim plugin, user-facing commands/setup configuration, help documentation, and a headless test harness in this currently greenfield repository.
- Uses Neovim buffer/window, asynchronous process, and Tree-sitter APIs; structural scopes depend on an installed parser and supported language queries.
- Adds an optional Diffview integration with a narrow compatibility boundary for comparison metadata and layout events; Git supplies versioned review content.
- Requires a separately installed and authenticated external AI tool. Initial output integrations target OpenCode, Codex, and a plain structured-output command, with an escape hatch for custom decoding.
- Sends assembled code/review context to the configured command; that tool's provider, permission, retention, subscription, and billing settings remain in effect.
- This change creates planning artifacts only. Plugin implementation is a subsequent, explicitly requested apply phase.
