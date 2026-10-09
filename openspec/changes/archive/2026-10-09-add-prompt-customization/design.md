# Design

## Context

See `proposal.md` for motivation and `specs/external-agent-execution/spec.md` for the behavior contract.

`prompt.lua` owns hardcoded task instructions and version-1 code/file/hunk contracts, plus version-3 annotation/reduction/synthesis contracts. `model.lua` validates decoded responses before installation. The external command receives one stdin prompt, so there is no provider-independent system/user message-role hierarchy to enforce preference precedence.

`session.lua` already deep-copies configuration at invocation. However, prompt construction currently receives no customization, and `diff.lua` calls the prompt builder repeatedly during auto/focused context selection. Review planning and completed-record replay build prompts from captured job configuration. `identity.lua` explicitly selects generation inputs rather than hashing all setup options, so adding a top-level table alone would not affect answer keys.

## Goals / Non-Goals

**Goals:**
- Preserve one plugin-owned prompt construction path for budgeting and dispatch, with explicit preference precedence and no wire-schema changes.
- Carry the same captured customization through collection, planning, dispatch, cache lookup, and review replay/resume.
- Make technical and business-oriented perspectives examples of arbitrary compatible customization, not separate execution modes.

**Non-Goals:**
- Full prompt replacement, string templates, prompt-transform callbacks, per-phase public knobs, file-backed prompts, per-request UI selectors, or named profiles.
- Detecting contradictory natural-language instructions during setup or proving that an agent obeys compatible preferences.
- Provider-specific structured-output integrations, automatic repair/retries, stronger external sandboxing, or changes to validation semantics.
- Loading additional project documents or expanding supplied coverage because a preference asks for business context.

## Decisions

### 1. Four string slots, empty by default

Add `prompts = { common = "", code = "", diff = "", review = "" }` to setup defaults. Validate the table and known string slots using existing setup patterns. Preserve supplied strings exactly; do not trim, interpret templates, or inspect their natural-language meaning. Empty strings contribute no preference text. Setup's existing reset and deep-copy behavior applies.

Use this applicability matrix:

| Request | Applicable slots, least to most specific |
| --- | --- |
| Code file or selection | common, code |
| Diff file or hunk | common, diff |
| Review annotation | common, diff |
| Review reduction | common, diff, review |
| Review synthesis | common, diff, review |

The review slot shapes the narrative and therefore also informs reduction, where relevant findings can otherwise be lost before synthesis. It does not alter file annotations. Users wanting business-oriented file notes and narrative set `diff`; users wanting only narrative organization set `review`.

Prefer these slots over a technical/business enum because users can express other perspectives without API expansion. Prefer strings over callbacks to keep configuration capture, byte budgeting, and identity deterministic. Specific preferences resolve conflicts with common preferences only; all slots remain below mandatory constraints.

### 2. Separate JSON-encoded preferences from authoritative rules

Keep selection/composition in `prompt.lua`, shared by its existing builders. Build a separate block containing only nonempty applicable slot values via `vim.json.encode`; never splice user text into contract fields or interpolate it as a prompt template. Keep repository text and derived findings in their existing untrusted source blocks.

The assembled prompt has this conceptual layout:

```text
PLUGIN-OWNED TASK AND GROUNDING RULES
PLUGIN-OWNED CUSTOMIZATION PRECEDENCE RULES
USER CUSTOMIZATION - SUBORDINATE PREFERENCES: <JSON object>
MANDATORY OUTPUT CONTRACT: <plugin-owned schema>
UNTRUSTED SOURCE/REQUEST DATA: <existing JSON blocks>
```

The precedence rules explicitly identify customization as user input and say it cannot override output versions/schema, required fields, request/snapshot/unit/child identities, anchors, evidence, coverage, resource limits, task boundaries, or action restrictions. Ignore conflicting portions while retaining compatible ones. Business emphasis does not authorize inventing rationale, claiming omitted context, omitting assigned units, or exploring the repository. No warning text is requested outside the valid JSON response.

Omit the customization block when all applicable slots are empty. Keep the mandatory task rules and contracts regardless of customization. Plugin-owned wording and JSON encoding communicate a boundary, but do not enforce model obedience. Existing output validation remains authoritative for machine-checkable rules; external command permissions remain authoritative for tool restrictions. Rejected responses follow normal failure behavior.

### 3. Budget the actual customized prompt throughout the existing pipeline

Extend existing prompt builder inputs to receive captured slots, rather than reading global setup state. Session dispatch passes the captured table. Diff collection receives the same table through its existing options and supplies it to every prompt-size probe: size-only preflight, mandatory capacity, radius reduction, optional-document admission, and final full-prompt checks. Do not store preferences as source evidence in snapshots or reusable serialized context blocks.

Review request construction passes captured preferences to annotation, reduction, and synthesis builders. The same construction must be used for planning, dispatch, resumed work, and completed-record replay. Preserve existing input caps, output allowances, mandatory source coverage, and failure semantics. A long preference can reduce affordable optional diff context or increase review call count; it cannot be silently clipped to fit.

Adding preferences only at dispatch was rejected because focused collection could otherwise admit a target/context combination that cannot fit its final prompt. Do not use an estimated fixed allowance when the actual escaped preference block can be measured.

### 4. Include normalized slots in generation identity

Add the four normalized slots to `identity.lua`'s hashed generation inputs, defaulting missing values to empty strings even for internal callers that do not pass a full setup result. Hash the full normalized table conservatively: changing any slot invalidates answer/job identity, even when that slot does not apply to the current scope. This avoids a second phase-specific identity scheme and aligns with captured-configuration matching; the trade-off is some unnecessary misses.

Existing invocation-time configuration copying and queue equivalence preserve preferences. Review job IDs derive from semantic keys, while checkpoint reuse also checks captured configuration; ensure normalized defaults are consistent when review creation receives partial internal configuration. No active request consults newly configured slots mid-run.

Bump `PROMPT_VERSION` for changed plugin-owned instructions and generation behavior; keep wire response versions and persistent envelope/storage format unchanged. Persistent records contain only digests and validated answers, not raw preference tables or prompts. Preferences may influence answer prose, so existing plaintext-result disclosures still apply.

### 5. Verify host guarantees without pretending to test model obedience

Extend existing tests rather than adding a parallel test framework. Use distinct asymmetric sentinel preferences to detect slot leakage between code, diff, and review phases. Cover multiline/escaped/multibyte text and exact byte boundaries, and use inputs where customization changes optional-context admission or review planning.

Through setup and session/public explanation flows, verify invocation-time capture, mismatching cache misses, matching cross-session reuse, and review resume behavior. Use the offline command fixture to return an incompatible response to a conflicting customization and verify rejection. Existing model tests already enforce the schema; avoid redundant tests of unchanged validator internals.

Tests establish that the prompt retains mandatory rules, transmits applicable preferences correctly, and rejects invalid output. They cannot establish that arbitrary providers reliably choose a business perspective or disregard every conflicting instruction. An optional live-agent experiment can assess explanation quality, but is not an acceptance gate or a reason to claim an enforcement guarantee.

## Risks / Trade-offs

- [Agent treats preference text as higher-priority instructions] -> Explicit plugin-owned hierarchy and separate encoding; unchanged host validation rejects structural violations. Prompt wording does not guarantee semantic accuracy or external tool safety.
- [Business perspective invites unsupported motive claims] -> Retain evidence and intent distinctions, and demonstrate grounded business-rule examples rather than invented business rationale.
- [Long preferences reduce context or increase review costs] -> Count actual serialized bytes at all admission points; retain omission disclosures and actionable failures without truncation.
- [Review reduction drops narrative-relevant findings] -> Apply review preferences to reduction and synthesis, while preserving child acknowledgements, supplied evidence, and reduction limits.
- [Unnecessary misses when an unused slot changes] -> Accept conservative full-table identity for simplicity; no need for phase-sensitive cache optimization in this change.

## Migration Plan

This is an additive setup change with empty defaults; no user migration or transport update is required. Document the slots and precedence in README, main help, and agent-contract help, including both technical and business examples. The prompt identity bump makes older answers ordinary misses without deleting or migrating cache records. Reverting the implementation restores the prior configuration behavior and identity version; no external state changes are involved.
