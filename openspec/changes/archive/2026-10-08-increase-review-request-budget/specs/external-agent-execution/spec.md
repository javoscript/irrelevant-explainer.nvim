# Spec Delta

## MODIFIED Requirements

### Requirement: Review resource limits

Review SHALL expose positive finite integer limits: request_max_bytes=262144, response_max_bytes=32768, max_snapshot_bytes=16777216, and max_requests=128 under review configuration. Each prompt SHALL fit both context.max_bytes and review.request_max_bytes. Responses SHALL fit the decoded JSON byte cap. The snapshot cap SHALL apply to canonical serialized review data; max_requests SHALL bound new external calls in each explicit run or resume, across every phase.

#### Scenario: Default review request budget
- **WHEN** review limits are not explicitly configured
- **THEN** the request cap is 262144 UTF-8 bytes, matching the default context.max_bytes
- **AND** the response, snapshot and invocation defaults remain 32768 bytes, 16777216 bytes and 128 calls respectively

#### Scenario: Explicit smaller request or context budget
- **WHEN** review.request_max_bytes or context.max_bytes is explicitly set to 65536 while the other cap is 262144
- **THEN** every complete review prompt remains bounded to 65536 UTF-8 bytes rather than using the larger default

#### Scenario: Raising the old input limit
- **WHEN** context.max_bytes is increased above review.request_max_bytes
- **THEN** review invocations retain the smaller review-specific cap rather than growing into one oversized request

#### Scenario: Exact UTF-8 boundary
- **WHEN** a complete prompt or decoded response including multibyte text equals its effective byte cap
- **THEN** the size check accepts it, while a value one byte above is rejected without truncation
- **AND** prompt instructions, schemas, targets and evidence count toward the input cap

#### Scenario: Exhausted invocation allowance
- **WHEN** a run has already launched max_requests external calls and still has work remaining
- **THEN** it stops before another dispatch, keeps valid checkpoints, and requires a new explicit resume to authorize another bounded run
- **AND** resumed cache hits do not consume external-call allowance

#### Scenario: Invalid limit
- **WHEN** a review limit is zero, negative, fractional, infinite, or not numeric
- **THEN** setup rejects it rather than silently disabling the bound
