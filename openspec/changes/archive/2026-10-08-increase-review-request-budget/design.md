# Design

## Context

See `proposal.md` for motivation. Public setup and the review planner separately declare the 65536-byte request default in `lua/explainr/init.lua` and `lua/explainr/review.lua`. Planning already uses the smaller context/review cap and fragments files that cannot fit. Configuration values already participate in completed-result and checkpoint identity.

## Goals / Non-Goals

**Goals:** Keep both runtime default declarations, configuration examples and tests consistent with the updated review resource contract.

**Non-Goals:** No default-sharing refactor, protocol change, provider configuration, automatic retry, output-limit increase, mandatory overview, or UI change.

## Decisions

- Set both existing request default declarations to 262144 without introducing an abstraction. Keeping 65536 fragments the reported file; 131072 also remains too small. Matching the existing 262144 context default is a simple, bounded choice rather than adopting the user's 10 MiB context override as a global default.
- Leave the response cap and output-aware packing unchanged. More input capacity permits whole-file reasoning but is not permission for unlimited output.
- Add a portable synthetic old/new file-pair regression in `tests/review_test.lua`, using unequal side lengths and a serialized whole-file prompt between 65536 and 262144 bytes. Verify a whole-file unit with omitted review configuration, fragmentation with either an explicit smaller review cap or smaller context cap, and complete coverage in each case. Do not depend on the user's external repository or invoke a provider.
- Rely on existing configuration identity rather than bumping prompt/planner versions: changing the configured default changes semantic identities for default users, while explicit existing overrides retain their behavior.

## Risks / Trade-offs

- Larger requests may exceed provider context limits, compact or time out → Keep the byte-versus-token caveat and explicit smaller-cap configuration; do not claim live provider acceptance from offline tests.
- A larger whole-file unit still has sparse note limits → Preserve existing output limits and avoid promising the same note count as fragmented reviews.
- Updating only one default would create inconsistent entry paths → Verify both public setup and direct planner default behavior.

## Migration Plan

After implementation, reload the plugin or restart Neovim to use the new default. Explicit `review.request_max_bytes` and smaller `context.max_bytes` overrides remain authoritative. No cache deletion or format migration is needed. Reverting both defaults restores prior planning behavior; this change does not alter local user configuration.
