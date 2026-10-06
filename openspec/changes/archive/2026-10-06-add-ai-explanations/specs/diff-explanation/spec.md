# Spec Delta

## Purpose

Explain focused code changes in the context of the complete review comparison, connecting implementation to cross-file requirements, decisions, and tests.

## ADDED Requirements

### Requirement: Exact review comparison

Diff explanations SHALL use the entire comparison selected in Diffview, with explicit old/new identities and a complete changed-file manifest. The plugin SHALL support two-way text comparisons and SHALL report unsupported or ambiguous comparisons rather than substituting a default working-tree diff.

#### Scenario: Review differs from working-tree diff
- **WHEN** Diffview compares two revisions and the working tree contains unrelated edits
- **THEN** the request uses the displayed revision comparison and excludes unrelated working-tree changes

#### Scenario: Working version has unsaved changes
- **WHEN** a supported comparison includes a working-buffer side with unsaved changes
- **THEN** the snapshot reflects those buffer contents and its patches agree with the displayed comparison

#### Scenario: Unsupported conflict or mixed comparison
- **WHEN** the view is a merge-conflict layout or its selected review scope has no unambiguous old/new comparison
- **THEN** the plugin reports the unsupported comparison without invoking AI on a guessed pair

### Requirement: Whole-comparison context with focused output

Every diff explanation request SHALL include all textual patches in the selected comparison, while identifying one focused file or hunk as the annotation target. It SHALL include that file's complete available before/after contents and restrict note anchors to the target.

#### Scenario: Related changes outside the visible file
- **WHEN** the user explains a policy hunk while a controller and tests are changed elsewhere in the same comparison
- **THEN** all three files' patches are supplied as context while line-aligned notes target only the selected policy hunk

### Requirement: Decision documents as context

Requests SHALL include complete available before/after versions of changed textual decision and documentation files in addition to their patches. Decision context SHALL not be restricted to OpenSpec and SHALL remain data rather than instructions granting the agent permission to act.

#### Scenario: Business rule in an OpenSpec change
- **WHEN** a review adds an owner-only cancellation requirement in an OpenSpec artifact and an ownership check in code
- **THEN** the code explanation request includes the complete artifact and asks the agent to relate the ownership check to that requirement

#### Scenario: Rationale outside changed document lines
- **WHEN** an ADR changes one paragraph but an unchanged paragraph explains the constraint behind the code change
- **THEN** the request contains the complete relevant document version, including the unchanged rationale

#### Scenario: Instructions embedded in a changed file
- **WHEN** a changed document tells an agent to ignore its output contract or execute a command
- **THEN** the prompt identifies repository content as untrusted contextual data, not controlling instructions

### Requirement: Evidence and intent distinctions

Requests SHALL ask the agent to distinguish documented intent, inferred intent, and unknown intent, and to identify visible mismatches between decisions and code. Notes claiming documented intent SHALL cite supplied evidence by path, version, and line range; absent rationale SHALL not be invented.

#### Scenario: Cross-file rationale
- **WHEN** a returned note labels its rationale as documented
- **THEN** its expanded detail exposes a citation to an existing supplied document or test range

#### Scenario: Code conflicts with the requirement
- **WHEN** the supplied requirement restricts cancellation to owners but the patch also allows editors
- **THEN** the prompt asks for the discrepancy to be explained rather than assuming that the implementation fulfills the requirement

#### Scenario: No decision document
- **WHEN** the comparison has no supplied evidence explaining why a change was made
- **THEN** the prompt asks the agent to explain the observable effect and label any proposed rationale as inference

### Requirement: Old and new anchors

Diff notes SHALL identify old-side, new-side, or paired old/new line ranges. Added and deleted files SHALL distinguish absent versions from empty existing files. Deleted-line notes SHALL remain associated with old code even when the new-side display contains only filler rows.

#### Scenario: Replacement shifts line numbers
- **WHEN** an old expression at line 59 becomes a new expression at line 62
- **THEN** the note can identify both ranges without treating old and new line numbers as equal

#### Scenario: Deletion-only hunk
- **WHEN** a hunk removes code without adding replacement lines
- **THEN** its explanation has a valid old-side anchor and can be displayed at the corresponding deleted-code row

#### Scenario: Added, deleted, renamed, and binary files
- **WHEN** the review includes these file statuses
- **THEN** the manifest preserves paths and statuses, textual changes remain included, and binary content is identified as unavailable for line explanation rather than misrepresented as an empty file

### Requirement: Complete-context budget

The plugin SHALL check the complete assembled request against an explicit context budget before invoking AI. If it exceeds the budget or required textual content cannot be collected, it SHALL report the problem and SHALL NOT silently omit files, truncate documents, or substitute a summary.

#### Scenario: Review exceeds budget
- **WHEN** the complete request exceeds the configured budget even though the focused file alone would fit
- **THEN** no command is started and the user sees the estimated request size and the option to increase the budget or select a smaller comparison

#### Scenario: Required version cannot be read
- **WHEN** a textual file version required for the comparison cannot be collected
- **THEN** the plugin reports the missing content and does not claim to have supplied the whole comparison

### Requirement: Review snapshot freshness

Results SHALL be bound to both the whole-comparison snapshot and the focused target. File switches, revision changes, relevant buffer edits, review refreshes, and view closure SHALL invalidate affected pending results; changed comparison content SHALL invalidate cached explanations.

#### Scenario: Another file changes during generation
- **WHEN** a decision document in the review changes while a code explanation is pending
- **THEN** the result from the older whole-review context is not displayed as current

#### Scenario: Switch focused file
- **WHEN** the user changes files before the prior request completes
- **THEN** its result cannot replace the explanation of the newly focused file
