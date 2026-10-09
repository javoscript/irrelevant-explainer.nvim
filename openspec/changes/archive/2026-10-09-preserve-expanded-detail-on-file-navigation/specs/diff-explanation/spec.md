# Spec Delta

## MODIFIED Requirements

### Requirement: Per-file retention during the current run

Completed batches SHALL be retained in memory by repository, comparison/filter and file for the current Neovim run, including off-screen completions and review-generated file results. Navigation SHALL hide old notes and exit old-file detail without cancelling old-file requests or marking answers stale, preserving eligible expansion intent for the target file. Returning SHALL revalidate original target/coverage and restore valid batches without inference, accepting recreated clean buffers with identical content. Completed results SHALL also be eligible for validated cross-session caching.

#### Scenario: Return to an explained file
- **WHEN** the user explains two hunks, visits another file and returns without content changes
- **THEN** both accepted batches are restored with no extra AI call or navigation-only stale warning
- **AND** eligible expanded navigation opens the first restored note, while collapsed navigation leaves the overview collapsed

#### Scenario: Visit an unexplained file
- **WHEN** the newly selected file has no saved explanations or pending request and auto-explanation is disabled
- **THEN** the pane shows an empty unexplained state rather than the previous file's notes or a false stale message
- **AND** navigating from expanded detail does not itself start inference

#### Scenario: Real context changed while away
- **WHEN** saved file or decision/index/revision context changed before returning
- **THEN** restoration rejects affected saved batches instead of trusting old window IDs or cached answers

#### Scenario: File finishes while hidden
- **WHEN** A completes successfully while B is selected and the user later returns to unchanged A
- **THEN** A's saved answer is displayed after freshness validation without another external invocation

### Requirement: Diffview reading keymaps

File overview, expanded detail, and Review SHALL inherit Diffview file-navigation and explorer bindings, respecting configured remaps, custom actions and disabled mappings. Default Tab/Shift-Tab SHALL navigate files, leader-e SHALL focus the explorer and leader-b SHALL toggle it. Enter/K SHALL remain File expansion controls; Review Enter SHALL follow a validated file reference. Tab SHALL not expand details or switch modes without file navigation. Successful next/previous navigation SHALL follow the expanded-detail continuity contract.

#### Scenario: Navigate from expanded detail
- **WHEN** Tab selects the next diff file while detail is open
- **THEN** Diffview navigation executes normally and old-file detail exits
- **AND** the target file's first valid displayed note expands under the expanded-detail continuity contract
- **AND** retention and opt-in inference rules remain unchanged

#### Scenario: Customized explorer mapping
- **WHEN** the user remaps or disables a Diffview explorer action
- **THEN** Irrelevant Explainer honors that mapping configuration rather than hard-coding the original key or overriding its action

#### Scenario: Navigate from Review
- **WHEN** a Diffview action or explorer selection changes the file while Review is displayed
- **THEN** the pane switches to that file's File mode while retaining the narrative reading position and any pending generation
- **AND** Review does not supply expanded File-detail intent

#### Scenario: Remapped previous-file action
- **WHEN** a configured previous-file action selects another file while File detail is expanded
- **THEN** the target follows the same expansion rule as next-file navigation, without requiring Shift-Tab

#### Scenario: Navigation at a list boundary
- **WHEN** a next/previous action does not change the selected file
- **THEN** the current detail selection, reading position, focus, and source views remain unchanged

## ADDED Requirements

### Requirement: Expanded-detail continuity across files

Next/previous Diffview file navigation SHALL expand the target's first valid displayed note if File detail was expanded when navigation began, regardless of the originating window. Otherwise the target SHALL remain collapsed. This behavior SHALL require no configuration option and SHALL NOT apply to initial reader opening. Expansion intent SHALL NOT authorize inference; existing `diff.auto_explain` and explicit-request rules alone control generation.

#### Scenario: Expanded navigation with saved notes
- **WHEN** next/previous navigation starts with File detail expanded and the target has fresh retained notes
- **THEN** the first note expands after validation without an external-agent call

#### Scenario: Source-originated navigation
- **WHEN** the user navigates next/previous from a source window while the explanation pane has expanded File detail
- **THEN** the target's first valid note expands without taking focus from the source

#### Scenario: Explicitly collapsed before navigation
- **WHEN** the user collapses detail and then navigates next/previous to an explained file
- **THEN** the target remains in the aligned overview

#### Scenario: Unexplained target with Auto disabled
- **WHEN** expanded navigation reaches a file without valid notes or pending work and `diff.auto_explain` is false
- **THEN** the reader shows its existing empty or stale state without generating or fabricating a note
- **AND** a subsequent file navigation evaluates actual detail state rather than remembering a persistent expanded preference

#### Scenario: Unexplained target with Auto enabled
- **WHEN** expanded navigation reaches an eligible unexplained file and `diff.auto_explain` is true
- **THEN** only the existing automatic file request is started or queued
- **AND** its first valid note expands when available if the target's expansion intent remains eligible
- **AND** an empty completed answer leaves the reader collapsed without retrying inference

#### Scenario: Target already has pending work
- **WHEN** expanded navigation reaches a file with matching pending work, including a pending review supplying file notes
- **THEN** navigation does not start duplicate work
- **AND** the first valid target note expands on completion only if its expansion intent remains eligible

#### Scenario: Initial opening
- **WHEN** a code or diff File reader opens and receives generated or cached notes without expanded file-navigation intent
- **THEN** notes remain collapsed without an automatic expansion
