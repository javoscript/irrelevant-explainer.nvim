# Proposal

## Why

Moving to the next or previous Diffview file currently discards expanded reading mode, requiring another expansion for every explained file. Carrying that mode forward makes sequential reading smoother while an explicitly collapsed reader continues to show summaries.

## What Changes

- When next/previous file navigation starts with File detail expanded, expand the target file's first explanation in displayed order after its notes pass existing freshness checks.
- When navigation starts with detail collapsed, leave the target file collapsed. Initial reader opening and Review-to-File navigation remain collapsed.
- Apply the rule regardless of whether next/previous navigation originates in the explanation pane or a source window, respecting Diffview remappings and preserving focus and source positions.
- Keep expansion separate from inference: unexplained targets stay empty unless existing `diff.auto_explain` rules or an explicit request supply notes.
- Make deferred expansion target-bound and one-shot, so later navigation, reader interactions, invalidation, or closure cannot replay obsolete expansion.
- Add no setting, command, dependency, or persistent reading-mode preference.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-explanation`: Next/previous navigation retains expanded reading intent while preserving per-file retention, mapping configuration, and opt-in inference rules.
- `aligned-explanation-ui`: Expand the first displayed target note without stealing focus or moving source code; preserve cleanup and cancel obsolete deferred expansion.

## Impact

- `lua/irrelevant_explainer/session.lua`: Navigation lifecycle, asynchronous restoration, accepted-result display, and retirement of target-bound expansion intent.
- `lua/irrelevant_explainer/ui.lua`: Reuse existing in-pane detail selection and display ordering with focus-preserving automatic expansion.
- `lua/irrelevant_explainer/diffview.lua`: Navigation integration if needed to capture intent before source replacement, without changing configured actions or unrelated mappings.
- Existing Diffview/UI/session tests and the README/UI help text. Update the current spec scenario that unconditionally restores saved notes in overview.
- No changes to generation contracts, result/cache identity, configuration defaults, or external-agent usage policy.
