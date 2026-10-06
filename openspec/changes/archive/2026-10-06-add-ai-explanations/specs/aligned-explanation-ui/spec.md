# Spec Delta

## Purpose

Keep concise explanations beside their corresponding source display rows, with synchronized navigation and full detail available without disturbing code layout.

## ADDED Requirements

### Requirement: Aligned annotation pane

The plugin SHALL open a read-only explanation pane to the right of the source by default. Each visible note SHALL occupy one display row corresponding to its source anchor; other rows SHALL stay blank. Notes exceeding available width SHALL be visibly truncated rather than wrapped into additional rows.

#### Scenario: Sparse notes
- **WHEN** notes target source lines 40, 43, and 46
- **THEN** the pane leaves intervening rows blank and does not compress the notes into a continuous list

#### Scenario: Narrow pane
- **WHEN** a summary is wider than the explanation pane
- **THEN** the summary is truncated with an expansion indicator and subsequent notes retain their row positions

### Requirement: Source display geometry

Alignment SHALL follow source display rows rather than equal file line numbers. It SHALL account for wrapping, closed folds, and diff filler without changing source text or disabling the user's wrapping and folding settings.

#### Scenario: Wrapped source line
- **WHEN** a source line wraps over three display rows
- **THEN** its note occupies its first visible display row and the continuation rows do not displace subsequent notes

#### Scenario: Fold hides note anchors
- **WHEN** a closed fold contains annotated lines
- **THEN** the pane preserves the fold's display height, identifies any combined note as referring to folded content, and does not display hidden notes as if they belong to the next unfolded line

#### Scenario: Diff filler on the followed side
- **WHEN** old-side deleted lines appear as filler in the followed new-side window
- **THEN** the corresponding old-side notes align with those comparison rows without adding lines to the source buffer

### Requirement: Synchronized navigation

Scrolling either paired pane SHALL preserve the correspondence between source and note rows. Moving to a note SHALL identify its source range; navigation SHALL avoid feedback loops and preserve the source comparison's existing diff synchronization.

#### Scenario: Scroll from the source
- **WHEN** the user scrolls the source by a viewport, including through folded or wrapped content
- **THEN** the note pane updates to the same visible source rows

#### Scenario: Scroll from the explanation
- **WHEN** the user scrolls within the explanation pane
- **THEN** the paired source view moves to the corresponding position and annotation alignment remains intact

### Requirement: Floating detail

Users SHALL be able to expand a visible note into a temporary floating window containing its full detail and evidence. Expansion SHALL use the already returned explanation and SHALL NOT make another AI call, insert annotation rows, or move the underlying source view.

#### Scenario: Expand and close detail
- **WHEN** the user opens a truncated note's detail and then closes it
- **THEN** the full explanation is readable and both paired panes retain their previous positions and alignment

#### Scenario: Several notes share a display row
- **WHEN** separate valid notes project to one folded or shared diff row
- **THEN** the row indicates combined detail and expansion exposes each note with its original source anchors

### Requirement: Diff isolation

The explanation pane SHALL remain outside the source diff comparison and native bound-window membership. Opening, scrolling, resizing, or closing it SHALL not compare prose against code, disable existing diff synchronization, or leave source window options changed.

#### Scenario: Explanation beside Diffview
- **WHEN** the pane is opened in a synchronized two-way Diffview layout
- **THEN** the source sides remain synchronized and only the original code buffers participate in diff computation

### Requirement: Lifecycle and status

The UI SHALL identify pending, failed, and stale explanation states separately from valid notes. Closing the source/view or explicitly disabling explanation SHALL close its pane and detail, cancel owned pending work, and remove its event handlers without changing unrelated windows.

#### Scenario: Failure after previous success
- **WHEN** a refresh fails while an older explanation exists
- **THEN** the pane identifies the failure and does not present older notes as a successful fresh result

#### Scenario: Source closes
- **WHEN** the paired source window or Diffview view closes
- **THEN** its explanation pane, floating detail, and pending request are cleaned up
