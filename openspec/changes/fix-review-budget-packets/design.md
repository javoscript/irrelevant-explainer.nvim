# Design

## Context

See `proposal.md` for motivation. This is a retrospective design record for the already-implemented fixes. Review capture, sequencing, freshness, and atomic acceptance retain their existing contracts.

`review.lua` plans request-local excerpts and output allowances, aggregates annotation findings into children, and reconstructs original cited source for reduction/synthesis. `model.lua` validates transmitted ranges rather than the complete retained snapshot. `identity.lua` versions prompt/planner semantics for checkpoint and completed-result reuse.

Reported failures included an 8192-byte unit overflow, a 69756-byte reduction request against a 65536-byte cap, and an unsent-range rejection in a larger split review. Offline fixtures reproduce wasted unit capacity and indivisible treatment of a multi-finding bundle; the original provider responses were not available for replay, so these fixes do not guarantee that every reported packet or future model response is affordable or correctly grounded.

## Goals / Non-Goals

**Goals:**

- Improve budget utilization without increasing configured resource limits.
- Make the indivisible reduction boundary one finding plus all its cited source, not one annotation call's entire output.
- Keep partition identities deterministic so checkpoint reuse and completed-record replay remain exact.
- Clarify source coordinates and rejection diagnostics without broadening citation authorization.

**Non-Goals:**

- Automatic repair, provider fallback, output clipping, source/evidence truncation, or partial new-review acceptance.
- Raising default request/response/call caps, managing provider token budgets, or changing external agent configuration.
- New reader layout, commands, transport decoders, protocol versions, or persistent unfinished jobs.

## Decisions

### Share spare unit capacity while preserving sparse output

`limits(job, unit_count)` reserves at least 512 response bytes, increasing that reserve when the encoded annotation envelope plus array separators requires more. The remaining bytes are divided evenly among assigned units. Both request and snapshot IDs are fixed-length hashes, so the envelope can be measured before computing the request identity.

Default annotation packing still admits up to three units based on the existing conservative output-packing rule. One, two, and three units receive 32256, 16128, and 10752 bytes respectively under the default response cap. Existing note/finding counts and individual text ceilings remain unchanged.

Keeping the fixed 8192-byte limit would unnecessarily reject affordable output. Increasing the global response cap instead would weaken the configured resource contract; removing per-unit bounds would allow one unit to consume siblings' allocated capacity.

### Partition only oversized child bundles

Before reduction grouping, children with multiple findings are checked individually for fit. Affordable children retain their original identity. An oversized bundle is expanded into single-finding children identified by a hash of the original child ID and finding index, then passed through the same bounded grouping path.

Each finding retains all evidence. Source excerpts are rehydrated from frozen originals and merged only across adjacent/overlapping supplied intervals. Per-group and per-level strict reduction progress checks remain unchanged. Splitting citation ranges or dropping evidence was rejected because it would change the grounding contract; splitting every affordable child was unnecessary overhead.

### Disclose bounds, never repair citations

Review excerpts include `end_line` beside `start_line` and unchanged source lines. Prompts explain 1-based chunk arithmetic, unavailable gaps, and fragment anchors versus larger original hunk metadata. Unsent-chunk validation errors identify the attempted path/side/range and first unsent line, without dumping source text.

Validation continues to derive supplied coverage from actual chunk starts and line arrays. The new endpoint is explanatory metadata, not permission to accept unsent text. Invalid model output still fails the invocation atomically rather than being clamped or normalized.

### Invalidate changed generation semantics

Prompt and planner identity versions advance from 1 to 2. This prevents old checkpoints or completed answers from aliasing reconstructed requests with changed allowances, excerpt metadata, or reduction partitioning. Cache format and review wire version remain unchanged.

## Risks / Trade-offs

- More reduction groups can increase latency and external-call consumption → Retain sequential dispatch, strict progress checks, call caps, and explicit resume using matching successful checkpoints.
- A single finding plus evidence or mandatory manifest can still exceed the input cap → Fail explicitly without truncation; no universal capacity guarantee is introduced.
- Models can still violate size or coordinate instructions → Enforce all existing validation and make unsent-range errors specific; no live-provider success claim is made.
- Added prompt/coordinate metadata consumes input bytes and can change splitting → Continue measuring every complete serialized prompt and verify asymmetric fragment coverage and exact byte boundaries.
- Identity changes discard reusable old generation records → Document restart and fresh-generation behavior rather than trying to migrate incompatible checkpoints.

## Migration Plan

Load the updated plugin by restarting Neovim, then explicitly request review in the intended comparison. Previous generation identities become misses; no cache deletion, database migration, provider change, or wire-wrapper upgrade is required. Reverting the implementation and identity versions restores the former behavior; answers produced under the newer identities do not alias older requests.

## Verification Record

- The full offline suite passed with 324 tests before the final additional large-batch regression.
- The final targeted review/model/prompt/identity run passed 61 tests, including the 300-unit configured allocation boundary, multibyte unit output, partitioned reducer failure/resume, completed-record replay, strict indivisible-packet failure, exact excerpt coordinates, and unsent-range diagnostics.
- No authenticated provider calls were made. Main specs remain unchanged pending explicit synchronization or archival.
- A subsequent user-run live review stopped at 6/35 units on an 11817-byte annotation request with `unknown section file_id`. Annotation findings reuse section validation, so this identifies an invalid finding reference against that request's manifest, not a narrative-phase or input-budget failure. The error omits the returned ID; its exact value and the model's reason for emitting it remain unverified. This change does not claim to resolve that provider-output failure.
