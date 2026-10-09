# Proposal

## Why

The 64 KiB review request default fragments ordinary old/new file pairs even when the existing 256 KiB context default could accommodate them, preventing those units from requesting file overviews. Offline planning of the reported file produced 19 fragments at both 64 and 128 KiB, but one whole-file unit with a 144,696-byte prompt at 192 and 256 KiB.

## What Changes

- Raise the default `review.request_max_bytes` from 65536 to 262144 (256 KiB), matching the existing `context.max_bytes` default.
- Preserve explicit overrides and the effective cap `min(context.max_bytes, review.request_max_bytes)`.
- Keep response, snapshot, invocation and timeout defaults unchanged; retain fragmentation above the effective cap.
- Update configuration examples and default assertions, and add a regression covering a file pair larger than the old cap but smaller than the new cap.
- Leave overview optionality, rendering, provider configuration and token accounting unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `external-agent-execution`: Change the review request byte default while preserving configured bounds and the other resource defaults.

## Impact

- Runtime defaults in `lua/explainr/init.lua` and `lua/explainr/review.lua`.
- Default and planner regression coverage in `tests/review_test.lua`, and documented defaults in `README.md` and `doc/explainr.txt`.
- Larger affordable requests may reduce fragmentation and invocation count, but do not guarantee provider acceptance or an overview. Existing configuration identity already distinguishes request limits; no protocol or cache-format migration is required.
- This change does not modify local Neovim configuration, unrelated loading-feedback work, or other active OpenSpec changes.
