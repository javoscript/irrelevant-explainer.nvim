# Spec Delta

## MODIFIED Requirements

### Requirement: Detail gutter lifecycle isolation

The detail gutter SHALL remain scoped to expanded explanation content. Collapse and file replacement SHALL restore the overview gutter before any eligible target-file expansion; cleanup SHALL not leave the detail gutter on surviving editor windows. Source and explorer gutters SHALL remain unchanged. These transitions SHALL remain error-free with automatic explanations enabled or disabled and preserve existing navigation and request behavior.

#### Scenario: Select another diff file while expanded
- **WHEN** a user opens diff explanations, expands a note, and selects another file through the Diffview explorer
- **THEN** the old detail exits and the explanation pane follows the selected file without gutter errors or stale detail rails
- **AND** source and explorer gutters retain their settings without Irrelevant Explainer stealing focus or applying the old detail cursor to replacement source buffers

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
- **AND** the pane restores the saved notes without retaining the old detail buffer or its gutter
- **AND** next/previous navigation that began with expanded File detail opens fresh target detail; navigation that began collapsed restores overview

#### Scenario: Cleanup leaves an ordinary editor window
- **WHEN** closing a source or view cleans up expanded explanations and an ordinary editor window survives or must be created to replace the last reader window
- **THEN** the remaining window does not inherit Irrelevant Explainer's detail-gutter expression
- **AND** drawing that window without explanation data produces no gutter errors

## ADDED Requirements

### Requirement: Automatic target-detail selection

Eligible expanded file navigation SHALL select exactly the first explanation in the target's displayed navigation order, not raw response order or cursor-overlap selection. Expansion SHALL reuse in-pane detail without a chooser or new layout, preserve focus, and add no source cursor or viewport movement beyond native file navigation. Existing manual expansion, note navigation, and collapse behavior SHALL remain unchanged.

#### Scenario: Response order differs from displayed order
- **WHEN** the target response lists a later-line note before an earlier-line note and expanded navigation is eligible
- **THEN** only the earlier displayed note expands
- **AND** the expanded header identifies the first explanation in displayed order

#### Scenario: Target has an overview
- **WHEN** a valid file overview is the first displayed note
- **THEN** automatic expansion selects it rather than a local note underneath the current source cursor

#### Scenario: Source stays away from the first note
- **WHEN** the first target note is outside the source viewport after native navigation
- **THEN** its detail uses the existing off-screen placement behavior
- **AND** automatic expansion does not jump the source cursor or viewport back to the note's anchor

#### Scenario: Different navigation origins
- **WHEN** eligible navigation originates in expanded detail or a source window
- **THEN** automatic expansion preserves the resulting active window and target source positions
- **AND** initialization events do not apply the new detail cursor to source code

### Requirement: One-shot target-bound expansion

Deferred automatic expansion SHALL belong only to its navigation target and SHALL run at most once after valid notes become displayable. Subsequent navigation, user focus change after navigation, reader movement or explicit detail choice, Review selection, invalidation, cancellation, failure, or closure SHALL retire it. Late callbacks and status, redraw, or layout events SHALL NOT reopen detail. No persistent expanded preference SHALL survive a target with no notes.

#### Scenario: Delayed restoration
- **WHEN** expanded navigation reaches retained notes whose freshness check is pending
- **THEN** the reader keeps its existing checking state until validation succeeds
- **AND** eligible target detail expands once, only after fresh notes can be displayed

#### Scenario: Navigate again before restoration completes
- **WHEN** expanded navigation from A reaches B, then the user navigates to C before B's notes become displayable
- **THEN** B's late callback cannot expand B or C
- **AND** C's navigation uses the actual detail state at that later navigation, not B's pending intent

#### Scenario: User leaves while waiting
- **WHEN** the user changes focus or tabs after initiating eligible navigation but before its notes arrive
- **THEN** later completion can install normally retained results but does not automatically open detail or switch focus
- **AND** returning focus does not revive that navigation's expansion intent

#### Scenario: User makes a reading choice while waiting
- **WHEN** the user moves in the reader, manually expands a note, or switches to Review before delayed target notes arrive
- **THEN** automatic expansion does not replace that choice

#### Scenario: Explicit collapse after automatic expansion
- **WHEN** the user collapses the automatically expanded target note and subsequent status, layout, or redraw events occur
- **THEN** detail remains collapsed without replaying the navigation's expansion

#### Scenario: Terminal result or invalidation
- **WHEN** the navigation target has no notes, becomes stale, fails, is cancelled, or its reader closes before expansion
- **THEN** no detail is fabricated or reopened by late callbacks
- **AND** the existing empty, stale, failed, cancelled, or closed state remains authoritative
