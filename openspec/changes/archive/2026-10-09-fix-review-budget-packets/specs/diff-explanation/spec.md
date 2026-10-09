# Spec Delta

## MODIFIED Requirements

### Requirement: Bounded evidence-grounded synthesis

Synthesis SHALL obey the same per-invocation limits as annotation. Oversized finding sets SHALL use bounded reduction with preserved child coverage and original cited source excerpts. Each reduction SHALL reduce the serialized findings/evidence input required by the next level. Unsplittable packets, nonreducing output, or exhausted call limits SHALL fail explicitly without unbounded recursion or oversized final requests.

An oversized child result containing multiple findings SHALL be partitioned by finding before it is classified as indivisible. Every finding and its complete cited original source SHALL remain represented, with deterministic partition identities supporting explicit resume and completed-record validation.

#### Scenario: Findings exceed the synthesis budget
- **WHEN** all validated annotation findings and their evidence cannot fit one synthesis prompt
- **THEN** bounded reduction processes all child results before final narrative synthesis, preserving exact source citation provenance through every level
- **AND** final synthesis does not request all file notes again

#### Scenario: Evidence exceeds a request
- **WHEN** an indivisible finding plus its cited original source cannot fit, or reduction does not decrease the next level's required bytes
- **THEN** the job stops with a synthesis-budget diagnostic and retains matching validated checkpoints rather than dropping evidence or looping

#### Scenario: Citation to another unit's unseen range
- **WHEN** a reduction or synthesis response cites valid local snapshot lines that were not supplied in that invocation
- **THEN** the response is rejected despite those lines having appeared in an earlier annotation request

#### Scenario: One annotation bundle exceeds the reduction budget
- **WHEN** one validated annotation child contains several findings whose combined packet cannot fit, but each finding and its complete evidence can fit individually
- **THEN** bounded reduction groups partitioned findings into affordable requests without dropping findings or truncating their evidence
- **AND** each request acknowledges its assigned deterministic child identities

#### Scenario: Resume and replay partitioned reduction
- **WHEN** partitioned reduction succeeds for one group and fails for a later group, then the user explicitly resumes unchanged content and configuration
- **THEN** successful annotation and reduction checkpoints are reused without repeating their external calls
- **AND** a completed record reconstructs the same partitions, request identities, and original evidence without inference
