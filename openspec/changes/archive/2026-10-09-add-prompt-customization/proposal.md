# Proposal

## Why

Users need to choose an explanation perspective, such as technical mechanisms or business rules and user-visible outcomes, without modifying the plugin's hardcoded prompts or configuring provider-specific agents. Open-ended customization must preserve the structured response protocol and grounding rules that make explanations parseable and safe to display.

## What Changes

- Add optional free-form `prompts.common`, `prompts.code`, `prompts.diff`, and `prompts.review` setup slots for perspective, emphasis, language, audience, tone, depth, and organization.
- Identify applicable customization as user-supplied subordinate preferences in every assembled prompt. Keep plugin-owned protocol, task, evidence, coverage, resource, and agent-action constraints authoritative.
- Apply code preferences to ordinary code explanations, diff preferences to diff explanations and all whole-review phases, and review preferences additionally to whole-review reduction and synthesis.
- Preserve version-1 and version-3 response contracts and existing validation/failure behavior; do not permit whole-template replacement or introduce automatic response repair.
- Include customization in invocation-time configuration capture, complete-prompt budgeting, diff context selection, review planning, and answer/checkpoint identity.
- Document technical-oriented and business-logic-oriented examples, slot composition, and the limits of prompt precedence versus host validation and external permissions.

## Capabilities

### New Capabilities

None. Prompt construction, validation, budgeting, and generation identity already belong to external-agent execution.

### Modified Capabilities

- `external-agent-execution`: Add user prompt customization with explicit subordinate precedence, deterministic slot applicability, customization-aware budgets and reuse, and unchanged response enforcement.

## Impact

- Public setup configuration gains an optional `prompts` table; existing configurations and command transports remain supported.
- Implementation touches `init.lua`, `prompt.lua`, `session.lua`, `diff.lua`, `review.lua`, and `identity.lua` under `lua/irrelevant_explainer/`.
- Extend existing setup, prompt, diff, review, identity, session, and persistence tests and the offline agent fixture as needed; update README and help documentation.
- No new runtime dependency, provider integration, UI control, protocol version, or external permission change. Prompt-generation identity will change to prevent reuse of pre-change answers under the new instructions; existing cache storage is not migrated or deleted.
