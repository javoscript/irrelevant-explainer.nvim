# Tasks

## 1. Increase the bounded request default

- [x] 1.1 Update default assertions in `tests/review_test.lua` to 262144 and add a portable asymmetric old/new file-pair regression whose complete prompt exceeds 65536 but fits 262144. Verify default planning retains a whole-file unit while an explicit 65536 review cap or context cap still fragments with complete coverage; run the targeted review suite before the runtime edits to confirm it detects the old defaults.
- [x] 1.2 Change the existing request defaults in `lua/explainr/init.lua` and `lua/explainr/review.lua` to 262144 without changing other limits, packing, validation, identity versions or overview policy. Run `EXPLAINR_TEST=tests/review_test.lua nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` and verify the default and smaller-cap regressions pass.
- [x] 1.3 Update the configuration examples in `README.md` and `doc/explainr.txt`, including the help budget table, to 262144. Verify examples match both runtime defaults and retain the effective-minimum and provider-token caveats; leave explicit 65536 examples and identity fixtures unchanged when they represent overrides rather than defaults.

## 2. Integrated verification

- [x] 2.1 Run `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`, `git diff --check`, and `openspec validate increase-review-request-budget --strict`; report actual outcomes and distinguish unrelated concurrent-work failures from this change without reverting other work. Do not claim live-provider acceptance from offline tests.

## Workflow follow-up

- After implementation and verification, sync this change's `external-agent-execution` delta and archive `increase-review-request-budget`, preserving all existing scenarios and unrelated active changes.
- Verify the archived artifacts exist and the main review resource requirement states request_max_bytes=262144 with unchanged response, snapshot and invocation defaults. Do not commit or push unless separately requested.

## Verification record

- Before runtime edits, the targeted suite reported 24 passed and two expected failures for the public and planner defaults still being 65536.
- After runtime edits, all 26 targeted review tests passed, including asymmetric whole-file planning and complete fragmented coverage under either smaller cap.
- The full offline suite passed with 329 tests and zero failures; no live provider calls were made.
- Strict change validation and `git diff --check` passed. Main-spec validation passed for all four capabilities, with existing long-requirement warnings outside this modified requirement.
