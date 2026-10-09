# repository-presentation Specification

## Purpose

Present Irrelevant Explainer as a personal-use Neovim showcase with a satirical identity, clear practical documentation, and explicit safety gates before public publication.

## Requirements

### Requirement: Public project identity

The repository SHALL present the plugin as **Irrelevant Explainer**, using `irrelevant-explainer.nvim` as the repository name, `irrelevant_explainer` as the Lua package, and `IrrelevantExplainer` as the command prefix. Current installation and integration examples SHALL use this identity and document migration from Explainr. Historical records and documented storage compatibility exceptions SHALL remain distinguishable from current public names.

#### Scenario: Reader installs the published plugin
- **WHEN** a reader follows the public installation and quick-start examples
- **THEN** repository coordinates, Lua imports, commands, and help references identify the same renamed plugin
- **AND** local-checkout instructions are supplementary rather than the only installation route

#### Scenario: Existing personal configuration
- **WHEN** an existing Explainr user reads migration instructions
- **THEN** the instructions identify changed imports, commands, mappings, help tags, filetype, highlight/status integrations, and the need to restart Neovim
- **AND** preserved historical names or cache paths are explained rather than presented as current entrypoints

### Requirement: Personal showcase positioning

The README SHALL prominently state that the plugin was developed for the author's personal use and is published for inspiration, inspection, and adaptation. It SHALL NOT imply a supported product, maintenance commitment, stable API, release cadence, roadmap, or broad compatibility guarantee. Describing how to run the plugin SHALL NOT be presented as a support promise.

#### Scenario: Visitor reads the introduction
- **WHEN** a visitor reads the README opening
- **THEN** the personal origin and showcase purpose are apparent before detailed setup instructions
- **AND** borrowing ideas is welcomed without promising ongoing support

### Requirement: Acidic editorial voice

The repository introduction, tagline, and selected editorial headings SHALL use dry, acidic, self-aware humour about human code comprehension becoming irrelevant in AI and agentic development. The joke SHALL target the premise, industry hype, and the plugin's own futility rather than demean users. Satire SHALL NOT masquerade as a technical claim that understanding code is unnecessary.

#### Scenario: Showcase introduction
- **WHEN** a visitor reads the project pitch
- **THEN** the name and copy convey the absurdity of engineering explanations for allegedly obsolete human understanding
- **AND** the voice is more distinctive than generic productivity marketing

### Requirement: Practical documentation remains reliable

Installation, technical help, diagnostics, privacy/security warnings, and explanation-generation instructions SHALL remain accurate and actionable. Editorial humour SHALL NOT request satirical generated explanations or weaken factual grounding. Documentation SHALL disclose external-tool source transmission and retention, plaintext result-cache risks, and the limits of provider compatibility testing.

#### Scenario: Reader configures an external agent
- **WHEN** a reader follows setup and privacy guidance
- **THEN** required tools, authentication ownership, permissions, possible code retention, and cache controls remain understandable without decoding a joke
- **AND** successful local validation is not described as proof of explanation truth or provider compatibility

### Requirement: Personally styled capability demonstrations

The README SHALL embed screenshots and GIFs of the running plugin showing aligned code/diff notes, detail expansion and synchronized navigation, and Review-to-file navigation. Captures SHALL use the author's personal Neovim configuration and styling, not a mockup or the default test theme. Synthetic content and offline fixture answers SHALL avoid private code and live inference; captions SHALL identify fixture demonstrations.

#### Scenario: Visitor previews the plugin
- **WHEN** a visitor opens the README on GitHub
- **THEN** embedded, readable media demonstrate the renamed plugin's code, diff, detail, and whole-review capabilities with the author's actual editor styling
- **AND** an animation shows real interaction rather than only a loading loop

#### Scenario: Personal configuration is used without disrupting personal work
- **WHEN** the demonstrations are captured
- **THEN** a disposable Neovim process loads the author's configuration and operates only on synthetic buffers and a disposable review repository
- **AND** personal configuration files, existing editor sessions, and saved personal results are not changed or cleared

### Requirement: Public-safe demonstration media

Every published image and GIF frame SHALL be reviewed for sensitive content, including source/prose, paths, names, identifiers, notifications, editor chrome, and file metadata. Only inspected final assets SHALL be included in the repository; raw captures SHALL remain excluded. Unsafe captures SHALL be replaced or safely sanitized and re-inspected before publication. A text secret scan alone SHALL NOT establish media safety.

#### Scenario: A notification exposes a private path for one frame
- **WHEN** any captured frame contains private information even if the first and last frames are safe
- **THEN** that asset is withheld until a replacement or sanitized final animation has been inspected throughout
- **AND** the unsafe raw image or animation is not staged or published

### Requirement: License and repository hygiene

The publication candidate SHALL contain an owner-approved license with required attribution and shared ignore rules for local artifacts, editor temporary files, Python bytecode, and local credentials. Ignore rules SHALL NOT conceal tracked sensitive content or exclude all development guidance. Licensing SHALL express reuse permission without implying maintenance or support.

#### Scenario: Candidate is prepared for public reuse
- **WHEN** the candidate is reviewed for publication
- **THEN** its license choice and attribution have been confirmed and local generated or credential files are excluded from accidental addition
- **AND** already-tracked files are still included in the sensitive-information audit regardless of ignore rules

### Requirement: Complete sensitive-information publication gate

Publication SHALL require a dedicated redacted secret scan of current candidate files and complete reachable history across all intended branches/tags, plus manual privacy review of files, deleted content, commit/tag messages, author/committer metadata, internal links, and images/binaries. The review SHALL state its scope, limitations, and unresolved findings without reproducing sensitive values. A shallow or partial scan SHALL NOT satisfy this gate.

#### Scenario: Secret exists only in a deleted historical file
- **WHEN** current files appear clean but an earlier reachable commit contains a credential
- **THEN** publication remains blocked pending credential rotation where applicable and approved remediation
- **AND** removing the file from the current tree or adding an ignore rule does not resolve the historical exposure

#### Scenario: Metadata contains a personal or work email
- **WHEN** history review finds identifying author or committer metadata without a credential leak
- **THEN** that finding is presented as a separate owner privacy decision
- **AND** metadata is not silently rewritten and a secret scanner is not claimed to decide whether it is suitable for publication

#### Scenario: Audit cannot cover the publication candidate
- **WHEN** historical objects, intended refs, binaries, or final candidate files have not been reviewed
- **THEN** the audit records the gap and the repository is not declared cleared for publication
- **AND** reports distinguish no detected matches from a guarantee of no sensitive information

### Requirement: Reproducible verification

The repository SHALL provide offline CI using documented Neovim versions, Python, and Git, with an explicit Diffview integration job and ongoing file/history secret scanning. Tests SHALL NOT need provider credentials or live inference. Integration CI SHALL fail when required dependencies are absent rather than report success after skipping their coverage. Candidate validation SHALL include clean-checkout installation/help checks and rendered renamed UI states.

#### Scenario: Diffview dependency is unavailable in integration CI
- **WHEN** the dedicated integration job lacks its required Diffview runtime or dependency
- **THEN** the job fails clearly instead of treating a skipped integration suite as successful coverage
- **AND** ordinary code-mode tests remain runnable without Diffview

#### Scenario: Candidate is reported ready
- **WHEN** local implementation is ready for publication review
- **THEN** the report identifies executed tests, clean-checkout checks, inspected UI states, and the final audit result with any limitations
- **AND** CI configuration is not claimed to have passed on GitHub unless it actually ran there

### Requirement: Explicit publication and remediation authorization

Creating an external repository, pushing refs, making it public, rotating credentials, or rewriting history SHALL require explicit authorization for the specific action. Preparation SHALL preserve history by default, leave unrelated local work untouched, and stop publication for unresolved sensitive findings. Readiness SHALL NOT be reported as committed, pushed, or published when those steps have not occurred.

#### Scenario: Local preparation is complete without publication approval
- **WHEN** the renamed candidate and local checks are ready but external publication has not been authorized
- **THEN** work stops at a reviewable ready-to-publish candidate and reports the remaining external steps
- **AND** no repository creation, push, or visibility change is performed automatically
