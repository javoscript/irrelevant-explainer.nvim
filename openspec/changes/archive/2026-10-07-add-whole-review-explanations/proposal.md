# Proposal

## Why

Diff explanations can resend the same comparison context once per file, yet offer no narrative connecting the changes across files. Navigating away also cancels unfinished explanations, wasting work the user may want when returning.

## What Changes

- Add `:ExplainrDiff review` and `require("explainr").diff("review")` to request a whole-change narrative and all eligible per-file explanations in one external-agent invocation. Keep the existing default file and explicit hunk scopes.
- Add Review/File reading modes in the existing right-hand pane (option A). Review is independently scrollable Markdown with validated file references; File retains aligned summaries and in-pane detail. Switching back to a generated narrative does not invoke AI.
- Keep file, hunk, and review requests alive across file navigation within the same comparison. Store off-screen completions against their original targets and revalidate before displaying them.
- Serialize inference per tab, deduplicate equivalent requests, preserve explicit queued work, and coalesce unstarted automatic navigation requests to the latest selected file. A pending whole-review request suppresses redundant automatic file requests.
- Preserve explicit Cancel/Close and stale-context safeguards. Scope Refresh to the visible reader mode and prevent background results from stealing focus or replacing an unrelated file/detail.
- Require complete review coverage within the configured prompt budget. Report oversized comparisons, unavailable content, and malformed/incomplete output explicitly; do not silently truncate, split into multiple invocations, or fall back to per-file generation.

## Capabilities

### New Capabilities

None. These behaviors extend the existing diff, reader, and external-agent contracts.

### Modified Capabilities

- `diff-explanation`: Whole-review scope and narrative, comparison-owned requests, cross-file queueing, retention, navigation automation, freshness, and mode-aware refresh.
- `aligned-explanation-ui`: Review/File modes, independently scrollable narrative with file navigation, nondisruptive completion, and visible current-file versus background request status.
- `external-agent-execution`: A review-specific versioned response containing narrative sections and per-file results, strict coverage/grounding validation, and request reuse independent of the displayed file.

## Impact

- Primary implementation areas: `lua/explainr/init.lua`, `diff.lua`, `diffview.lua`, `session.lua`, `prompt.lua`, `model.lua`, and `ui.lua`; transport decoders require compatibility tests rather than a new provider integration.
- Extend the existing model, prompt, diff, session, real-Diffview, and visual fixtures; update README and command/UI/agent help.
- Existing code/file/hunk version-1 payloads remain compatible. Custom commands used for review scope must support the new response shape. Navigation no longer implicitly cancels requests, and new explicit file requests queue instead of superseding compatible work; users retain explicit cancellation.
- No new mandatory dependency, persistent history, concurrent provider fan-out, automatic whole-review generation, floating summary window, or code-mode redesign.
