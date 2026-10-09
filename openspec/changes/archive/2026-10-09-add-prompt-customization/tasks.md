# Tasks

## 1. Setup slots and authoritative prompt composition

- [x] 1.1 Add the four empty-string `prompts` defaults and strict table/key/string validation in `init.lua`; extend setup tests in `tests/model_test.lua` to verify defaults, invalid values and unknown keys, caller isolation, reset semantics, and no process launch.
- [x] 1.2 Extend the existing builders in `prompt.lua` to accept captured slots, compose only applicable nonempty values as a separate JSON block, and include explicit plugin-owned precedence instructions without changing wire contracts; extend `tests/prompt_test.lua` to verify the code/diff/review phase matrix with distinct sentinel values, preference precedence guidance, conflicting format/tool requests, and exact escaped/multibyte string preservation.
- [x] 1.3 Document `common`, `code`, `diff`, and `review` defaults and applicability in README and `doc/irrelevant-explainer.txt`, and precedence versus host validation/external permissions in `doc/irrelevant-explainer-agents.txt`; verify technical/business examples use valid setup syntax and never suggest preferences can replace the schema, invent rationale, or authorize tools.

## 2. Captured preferences and complete-prompt admission

- [x] 2.1 Pass invocation-time slots from `session.lua` to dispatch and diff collection, and from captured review configuration to all phase builders in `review.lua`; extend session/review tests to verify a setup change during queued collection or between review phases does not replace the captured preferences, including outside-review handoff.
- [x] 2.2 Carry captured slots into every `diff.lua` prompt-size probe and admission check; extend diff tests with a boundary where customization forces auto/focused optional-context reduction while preserving required targets, plus strict review-context and mandatory-input overflow failures before inference.
- [x] 2.3 Include customization in annotation, reduction, synthesis, and replay planning budgets; extend prompt/review tests to verify exact UTF-8 cap acceptance, one-byte-over rejection, changed affordable annotation grouping, and reduction/synthesis overflow without clipping inputs or bypassing existing output limits.
- [x] 2.4 Exercise a customized public explanation through the offline command fixture, returning valid JSON and then incompatible prose or missing review acknowledgements; verify normal acceptance/rejection, preservation of older fresh results, no invalid completed cache entry, and no automatic repair or fallback in existing session/review tests.
- [x] 2.5 Update budget guidance in main/agent help to explain that customization consumes complete-prompt capacity and can reduce optional context or increase review calls; verify documentation retains mandatory-source preservation, byte-versus-token distinctions, and actionable failure guidance.

## 3. Answer and checkpoint identity

- [x] 3.1 Add normalized four-slot customization to hashed generation inputs in `identity.lua`, normalize partial review configuration consistently, and bump prompt identity without changing response/storage versions; extend existing identity tests to verify omitted/empty equivalence, changed preference misses, and unchanged semantic inputs matching despite transient editor changes.
- [x] 3.2 Extend existing session/persistence/review tests to verify matching customized answers reuse in memory and across restart, changed slots miss prior answers, and changed customization cannot resume older review checkpoints while unchanged customization can; inspect persisted records to verify raw preference configuration is absent.
- [x] 3.3 Update cache guidance in main/agent help for automatic preference identity, conservative invalidation when any slot changes, and ordinary misses for earlier prompt versions; verify no migration/deletion instruction is introduced and plaintext answer-prose disclosures remain clear.

## 4. Combined verification

- [x] 4.1 Run `bash tests/ci.sh base` and the existing integration mode with pinned Diffview/Plenary paths when available; verify customized code, diff file/hunk, and multi-phase review scenarios together without regressions, and explicitly report unavailable integration coverage rather than claiming it passed.
- [x] 4.2 Run `openspec validate add-prompt-customization --strict` and `git diff --check`; inspect the combined changes against all delta scenarios and confirm no protocol relaxation, external permission change, raw-prompt persistence, or UI behavior change was introduced.
