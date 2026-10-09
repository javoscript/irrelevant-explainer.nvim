# Spec Delta

## ADDED Requirements

### Requirement: Free-form prompt preference configuration

Setup SHALL accept an optional `prompts` table containing only string-valued `common`, `code`, `diff`, and `review` slots. Missing slots SHALL default to empty strings; empty slots SHALL add no preference text. These additive slots SHALL accept free-form preferences rather than fixed perspective presets. Unknown keys, non-table `prompts`, and non-string slot values SHALL fail setup. Setup SHALL isolate caller-owned options and reset unspecified slots on subsequent calls.

#### Scenario: Technical or business perspective
- **WHEN** a user configures a slot to emphasize technical mechanisms or business rules and user-visible outcomes
- **THEN** setup accepts the free-form string without requiring a predefined perspective name
- **AND** other preferences such as language, audience, or domain terminology remain expressible in the same slot

#### Scenario: Invalid customization configuration
- **WHEN** `prompts` is a string, contains an unknown slot, or a slot contains a function, number, or table
- **THEN** setup rejects the configuration with an error identifying the invalid option before inference

#### Scenario: Defaults and caller ownership
- **WHEN** setup receives custom slots and the caller later mutates its options table
- **THEN** the effective configuration retains the captured strings
- **AND** a subsequent setup call with no customization resets all slots to empty without starting an external command

### Requirement: Prompt preference applicability

Code file/selection requests SHALL use `common` and `code`. Diff file/hunk requests and review annotation SHALL use `common` and `diff`. Review reduction and synthesis SHALL use `common`, `diff`, and `review`; `review` SHALL shape narrative content and organization rather than source annotations. Prompts SHALL ask the agent to combine applicable preferences, with more specific slots resolving conflicts among preferences only, never overriding mandatory constraints.

#### Scenario: Separate explanation modes
- **WHEN** distinct sentinel preferences are configured in every slot and code selection or diff hunk is requested
- **THEN** the code request includes only common/code preferences and the diff request includes only common/diff preferences

#### Scenario: Whole-review phase composition
- **WHEN** an explicit review requires annotation, reduction, and synthesis
- **THEN** annotation receives common/diff preferences
- **AND** reduction and synthesis receive common/diff/review preferences so narrative emphasis is considered when retaining findings
- **AND** code preferences are absent from every review phase

#### Scenario: Common and specific preferences disagree
- **WHEN** common preferences request an introductory audience and the applicable more specific slot requests an expert audience
- **THEN** the prompt instructs the agent to favor the more specific audience preference while retaining compatible common preferences

### Requirement: Explicit subordinate customization boundary

Every customized prompt SHALL identify applicable slots as user-supplied subordinate preferences, serialized as JSON separately from source data. Plugin-owned instructions SHALL state that preferences never override protocol/schema, identities, anchors, evidence, coverage, output limits, task boundaries, or agent-action restrictions. Conflicting portions SHALL be instructed to be ignored while compatible portions remain applicable. Mandatory contracts SHALL remain plugin-owned.

#### Scenario: Mixed compatible and conflicting preferences
- **WHEN** customization asks for business impact but also prose outside JSON, omitted required citations, and tool use
- **THEN** the assembled prompt identifies the text as subordinate customization and instructs the agent to retain compatible business emphasis while ignoring conflicting format, evidence, and action requests
- **AND** the mandatory output contract and restrictions remain present and unchanged

#### Scenario: Delimiter-like text and multibyte input
- **WHEN** a customization contains quotes, newlines, backslashes, multibyte characters, or text resembling a protocol heading
- **THEN** its exact string value is preserved through JSON encoding inside the customization block rather than interpolated into plugin-owned rules or contract fields
- **AND** source content and derived findings remain separately identified as untrusted data

### Requirement: Customization preserves response enforcement

Customization SHALL NOT change response versions, required fields, anchor/evidence validity, review acknowledgements, coverage, or resource limits. All returned and reused answers SHALL undergo existing scope/phase validation. Invalid output SHALL fail normally without schema relaxation, partial acceptance, automatic repair, or provider fallback. Documentation SHALL distinguish mandatory prompt instructions from host validation and externally enforced agent permissions.

#### Scenario: Agent follows an incompatible format request
- **WHEN** a customized request successfully completes but returns prose instead of the required JSON
- **THEN** normal decoding or validation rejects the output before display or completed-result caching

#### Scenario: Agent skips required review work
- **WHEN** customization asks to discuss only business policy and an annotation response omits an assigned unit
- **THEN** the invocation fails coverage validation rather than treating the preference as permission to skip assigned source

#### Scenario: Business rationale remains unavailable
- **WHEN** business-oriented customization accompanies source without supplied rationale
- **THEN** mandatory instructions still require documented, inferred, and unknown intent distinctions and prohibit invented rationale
- **AND** documentation does not claim schema validation proves semantic truth or that prompt instructions sandbox the command

### Requirement: Customization-aware complete prompt budgets

Applicable preference text, JSON escaping, and boundary instructions SHALL count toward complete UTF-8 prompt budgets during diff context selection and every review phase's planning and dispatch. Existing optional-context reduction SHALL account for that overhead. Required source, preferences, and protocol text SHALL NOT be truncated to fit. Mandatory-input overflow SHALL fail actionably before the affected invocation; limits SHALL NOT be presented as provider token counts.

#### Scenario: Exact customized UTF-8 boundary
- **WHEN** an assembled prompt containing escaped and multibyte customization equals its effective input cap
- **THEN** the byte check accepts it and rejects the same prompt at a cap one byte smaller

#### Scenario: Customization changes affordable optional context
- **WHEN** a diff file/hunk request fits without customization but additional preferences make optional context unaffordable
- **THEN** auto/focused selection accounts for the customization when reducing optional coverage
- **AND** the complete required target and preferences remain intact, while strict review-context mode fails if complete coverage cannot fit

#### Scenario: Customization exceeds mandatory capacity
- **WHEN** preferences plus mandatory instructions and an indivisible target cannot fit the effective input cap
- **THEN** collection or planning fails before launching that invocation without clipping preferences or required source
- **AND** review annotation planning includes customization before any annotation process starts, with reduction and synthesis independently bounded

### Requirement: Captured customization and reuse identity

Requests SHALL capture prompt slots at invocation and retain them through queuing, collection, generation, and review phases. Answer caches and review checkpoints SHALL include normalized customization in generation identity so changed preferences cannot reuse mismatching answers or unfinished jobs. Omitted slots and explicitly empty slots SHALL have equivalent identities. Customization SHALL NOT be persisted as raw configuration or prompts in completed-result records.

#### Scenario: Setup changes while a request waits
- **WHEN** a request is queued with technical preferences and setup subsequently selects business preferences
- **THEN** the queued request uses its invocation-time technical preferences throughout collection and all generation phases
- **AND** later requests capture business preferences instead

#### Scenario: Changed perspective misses previous answers
- **WHEN** identical source is requested with changed customization in the same process or after restart
- **THEN** the prior completed answer is not considered a matching cache hit
- **AND** identical source and customization remain eligible for validated reuse

#### Scenario: Changed preferences do not resume an old review
- **WHEN** an unfinished review has validated checkpoints and a later explicit request changes customization
- **THEN** checkpoints from the older configuration are not resumed under the new preferences
- **AND** unchanged customization remains eligible for normal owner-local checkpoint reuse

#### Scenario: Empty configuration equivalence and storage privacy
- **WHEN** equivalent requests omit `prompts`, supply an empty table, or explicitly supply empty strings
- **THEN** their normalized customization identities match
- **AND** completed-result records contain customization identity only as digests, not raw preference strings, while answer prose remains subject to existing plaintext-cache disclosures
