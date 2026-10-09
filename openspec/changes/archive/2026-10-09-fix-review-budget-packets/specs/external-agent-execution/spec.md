# Spec Delta

## MODIFIED Requirements

### Requirement: Output-aware review planning

Review planning SHALL account for bounded note/finding/detail output as well as exact input bytes, publishing finite output allowances in each prompt and validating them in responses. Small inputs with many targets SHALL not imply unlimited combined output. Limits SHALL be described as host guardrails, not provider token counts, output-token controls, billing guarantees, or proof that external compaction cannot occur.

Annotation units SHALL share available response capacity after reserving the serialized envelope and array separators, rather than retain an unnecessarily fixed per-unit cap. Sparse note/finding/text ceilings and whole-response validation SHALL remain enforced. Prompts SHALL clarify that serialized unit limits include identities, anchors, evidence, and JSON escaping, and that count/text limits are ceilings rather than quotas.

#### Scenario: Many tiny files
- **WHEN** many small file targets fit the input cap but their allocated notes/findings exceed the response allowance
- **THEN** the planner creates multiple annotation requests rather than requesting unbounded detail in one answer

#### Scenario: Model exceeds its allowance
- **WHEN** a successfully completed JSON response exceeds declared note/finding/detail or decoded-byte limits
- **THEN** the invocation fails without clipping notes, accepting partial JSON, or automatically retrying it with another provider

#### Scenario: Provider rejects a bounded request
- **WHEN** the external agent reports context overflow, compaction failure, or output truncation despite the local bounds
- **THEN** the error remains visible with phase/request size context and advice to reduce review limits or scope
- **AND** Explainr does not change external agent configuration or claim a model-capacity guarantee

#### Scenario: Affordable unit output exceeds the former fixed cap
- **WHEN** one, two, or three units share a default 32768-byte annotation response and an encoded unit exceeds 8192 bytes while obeying all newly published allowances
- **THEN** its unit allocation is respectively 32256, 16128, or 10752 bytes
- **AND** the response is accepted only if its full serialized JSON and all other schema, size, coverage, and freshness checks pass

#### Scenario: Large configured annotation batch
- **WHEN** a configured response budget admits enough units that the serialized response envelope and array separators exceed the usual 512-byte reserve
- **THEN** the allocation reserves the actual larger overhead so all full unit allocations together still fit the response cap

## ADDED Requirements

### Requirement: Review chunk coordinate disclosure

Review requests SHALL disclose each supplied chunk's original inclusive start_line and end_line with its unchanged source lines. Prompts SHALL explain that lines[i] denotes start_line + i - 1 using a 1-based index, that gaps are unavailable, and that fragment anchors remain confined to assigned target ranges even when original hunk or manifest bounds are larger.

#### Scenario: Fragment starts after the beginning of a file
- **WHEN** an annotation request supplies a fragment beginning at an original line other than 1 and hunk metadata spans beyond that fragment
- **THEN** the chunk endpoints match the supplied original text exactly and the prompt distinguishes fragment coverage from full-hunk coordinates
- **AND** neither note anchors nor evidence are authorized by unsent hunk or manifest metadata

### Requirement: Unsent chunk range diagnostics

A range crossing or extending beyond supplied chunks SHALL remain invalid. Its validation error SHALL identify the exact path, side, attempted inclusive range, and first unsent line without disclosing source text or accepting the valid portion of a failed invocation.

#### Scenario: Note anchor extends past a supplied chunk
- **WHEN** a returned note anchors old-side lines 5-7 but only lines 5-6 were supplied
- **THEN** rejection identifies the attempted old-side range and line 7 as the first unsent line

#### Scenario: Finding evidence crosses a gap
- **WHEN** finding evidence cites new-side lines 1-3 of a document whose supplied chunks contain only lines 1 and 3
- **THEN** rejection identifies the document, new side, attempted range 1-3, and line 2 as the first unsent line
- **AND** no failed invocation output becomes a checkpoint or partial new review
