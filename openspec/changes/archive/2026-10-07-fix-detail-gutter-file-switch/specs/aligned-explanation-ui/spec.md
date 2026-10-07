# Spec Delta

## ADDED Requirements

### Requirement: Buffer-safe detail gutter

Detail-gutter rendering SHALL remain error-free when the displayed buffer has no detail decoration data, including during buffer replacement and cleanup. Missing data SHALL produce no active detail rail. Valid detail SHALL retain its existing active rail, wrapped-row coverage, and gutter spacing.

#### Scenario: Gutter evaluates without detail data
- **WHEN** a detail-gutter expression is evaluated during a transition on a buffer without detail decoration data
- **THEN** it renders without an active detail rail and without undefined-variable or invalid-argument errors
- **AND** repeated evaluations do not produce an error prompt or message flood

#### Scenario: Active and inactive detail rows
- **WHEN** expanded detail contains active prose, wrapped continuation, and inactive surrounding context
- **THEN** active displayed rows retain their rail and inactive rows remain rail-free
- **AND** the existing gutter and padding width remain unchanged

### Requirement: Detail gutter lifecycle isolation

The detail gutter SHALL remain scoped to expanded explanation content. Collapse and file replacement SHALL restore the overview gutter; cleanup SHALL not leave the detail gutter on surviving editor windows. Source and explorer gutters SHALL remain unchanged. These transitions SHALL remain error-free with automatic explanations enabled or disabled and preserve existing navigation and request behavior.

#### Scenario: Select another diff file while expanded
- **WHEN** a user opens diff explanations, expands a note, and selects another file through the Diffview explorer
- **THEN** the old detail exits and the explanation pane follows the selected file without gutter errors or stale detail rails
- **AND** source and explorer gutters retain their settings without Explainr stealing focus or applying the old detail cursor to replacement source buffers

#### Scenario: Select another diff file after collapse
- **WHEN** a user expands a note, explicitly collapses it, and selects another file through the Diffview explorer
- **THEN** the overview gutter remains restored throughout navigation and redraw
- **AND** no detail-gutter expression leaks into source, explorer, or replacement overview buffers

#### Scenario: Runtime automation remains navigation-only
- **WHEN** the user enables automatic explanations after opening the explanation pane and then switches to a coherent unexplained file, either from expanded detail or after collapse
- **THEN** toggling alone issues no request and the navigation issues exactly one file-scoped request
- **AND** repeated focus, layout, and redraw events produce neither duplicate requests nor gutter errors

#### Scenario: Disabled automation and saved-note restoration
- **WHEN** automatic explanations are disabled and a user navigates away after reading detail, then returns to an unchanged file with valid saved notes
- **THEN** navigation and restoration issue no automatic inference requests
- **AND** the pane restores the saved notes in overview without retaining the old detail buffer or its gutter

#### Scenario: Cleanup leaves an ordinary editor window
- **WHEN** closing a source or view cleans up expanded explanations and an ordinary editor window survives or must be created to replace the last reader window
- **THEN** the remaining window does not inherit Explainr's detail-gutter expression
- **AND** drawing that window without explanation data produces no gutter errors
