# Tasks

This retrospective checklist records completed implementation and verification, not a request to rerun implementation. Live-provider limitations are recorded in `design.md` separately from offline acceptance.

## 1. Share bounded annotation output capacity

- [x] 1.1 Allocate response capacity across assigned units after reserving the envelope and separators; verify one/two/three-unit multibyte outputs above 8192 bytes pass within their published limits in `tests/review_test.lua`.
- [x] 1.2 Account for larger response envelopes in configured large batches without changing sparse item ceilings; verify independently serialized 300-unit allocations fit the configured response cap, while increasing every allocation by one byte would exceed it.
- [x] 1.3 Update `doc/explainr-agents.txt` with shared allocations, serialized-field costs, and ceilings versus quotas; verify documented default allowances and unchanged resource configuration against generated requests and setup tests.

## 2. Partition oversized finding bundles

- [x] 2.1 Split only oversized multi-finding children using deterministic child/index identities, preserving all original evidence; verify the four distinguishable findings in an oversized bundle all reach bounded reduction requests with exact original source.
- [x] 2.2 Preserve checkpoint and replay semantics for partitioned groups; verify an injected second-reducer failure resumes without repeating accepted calls and completed records reconstruct and validate without inference.
- [x] 2.3 Keep truly indivisible findings, oversized manifests, nonprogress, and call-cap exhaustion explicit; verify their failure tests and repeated explicit resumes in `tests/review_test.lua`, and document single-finding indivisibility in agent help.

## 3. Clarify transmitted coordinates and validation errors

- [x] 3.1 Include exact original chunk end coordinates and clarify chunk arithmetic and fragment/hunk boundaries; verify asymmetric old/new coverage and unchanged source slices in review tests plus prompt instructions in `tests/prompt_test.lua`.
- [x] 3.2 Identify path, side, attempted range, and first unsent line without accepting partial output; verify note-anchor overflow, finding evidence across a gap, and a citation beginning in a gap in `tests/model_test.lua`, retaining existing strict response validation.
- [x] 3.3 Advance prompt/planner identity versions and document restart/fresh-generation behavior; verify identity tests and cross-process completed-record reconstruction while keeping cache format and wire versions unchanged.

## 4. Record and validate combined delivery

- [x] 4.1 Run the complete offline suite with `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`; record the 324-test passing run and subsequent 61-test targeted run including the final added large-batch regression in `design.md`.
- [x] 4.2 Create proposal, design, both capability deltas, and this completed task record; verify existing scenarios are retained, reported versus reproduced failures are distinguished, and the subsequent unknown-file-ID live failure is not represented as fixed.
- [x] 4.3 Validate the change with `openspec validate fix-review-budget-packets --strict` and check whitespace with `git diff --check`; retain the active change without syncing or archiving main specs.

## Workflow follow-up

- Review and explicitly synchronize/archive this implemented change when requested.
- Investigate the exact file ID returned by the subsequent failing live annotation before attributing its invalid reference to a particular model mistake or relaxing validation; that error remains a documented limitation, not a completed fix.
