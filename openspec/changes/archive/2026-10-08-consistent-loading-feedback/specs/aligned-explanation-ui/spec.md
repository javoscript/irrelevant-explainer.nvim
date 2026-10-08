# Spec Delta

## MODIFIED Requirements

### Requirement: Scoped animated loading

Active and queued request ranges matching the displayed code or diff File target SHALL receive a steady faint full-width tint with an animated cursor-width gutter rail and a smooth cascading glow. Off-screen requests SHALL use status without misplaced range decorations. A busy Review SHALL animate its own visible narrative viewport, including an empty narrative, independently of source ranges. Checking saved File explanations SHALL animate the displayed file's visible extent without requiring an inference request. Animation SHALL preserve accepted text and source diff highlights, update only visible decorations, and retain a steady rail on the focused logical cursor line rather than removing it. It SHALL stop on completion, failure, cancellation, staleness or closure and not modify global cursor or terminal redraw options.

#### Scenario: Narrative generation is pending
- **WHEN** Review is visible while a whole-review request is pending
- **THEN** the narrative body shows the loading tint and rail without rewriting retained prose or changing its cursor, wrapping or viewport
- **AND** the empty state also animates, leaving source windows unchanged
- **AND** leaving Review clears its decorations; returning resumes them only if the review is still busy

#### Scenario: Two hunks are waiting
- **WHEN** one hunk is being explained and another is queued for the displayed file
- **THEN** both matching explanation ranges animate, including wrapped/folded rows and deletion/EOF filler, while accepted notes remain readable

#### Scenario: Snapshot not yet collected
- **WHEN** a diff request begins before exact anchors are available
- **THEN** a matching displayed file request previews the whole source and a hunk request previews its cursor/native changed region until collected anchors replace the provisional range
- **AND** navigation to a different file removes those provisional decorations rather than transferring them

#### Scenario: Cursor is on a loading row
- **WHEN** notes or Review have focus during loading
- **THEN** the focused logical cursor line retains its loading rail at a steady intensity, including its wrapped segments, while other eligible rails continue animating
- **AND** accepted text and backgrounds remain steady, and the header spinner continues animating
- **AND** the plugin leaves guicursor and termsync unchanged and documents synchronized terminal output as a flicker dependency

#### Scenario: Saved file explanations are being checked
- **WHEN** returning to a previously explained diff file shows Checking saved explanations
- **THEN** the File pane shows a loading rail and tint over its visible file extent while restoration waits
- **AND** no inference request is required to display that loader
- **AND** restored notes appear only after the existing freshness checks succeed

#### Scenario: Restoration is superseded by navigation
- **WHEN** saved explanations for file A are still being checked and the user selects file B
- **THEN** A's loading feedback and late restoration callback cannot install notes or loading ranges for A into B
- **AND** B shows only its own restoration, request, or idle state

#### Scenario: Cached review is requested again
- **WHEN** an already displayed review is retained while a repeated review request checks its result context
- **THEN** the loader overlays the retained narrative without changing its buffer text, reading position, or source positions
- **AND** cached-ready status appears only after validation succeeds

#### Scenario: Saved narrative access is being checked
- **WHEN** display-only Review access is checking a saved narrative or its context
- **THEN** the visible Review body or placeholder animates without launching inference
- **AND** an already displayed unchanged narrative retains its reading position
- **AND** content not yet eligible for display under freshness rules is not exposed merely to populate the loader

#### Scenario: Review prose wraps across several screen rows
- **WHEN** a busy Review paragraph occupies four screen rows with blank logical lines before and after it
- **THEN** every visible paragraph segment and blank row has a loading rail without gaps at wrap boundaries
- **AND** scrolling until the first visible row is a wrapped continuation or resizing the pane retains complete visible coverage and unchanged native wrapping

#### Scenario: Review ends before the viewport bottom
- **WHEN** a busy Review has less text than fits in its content viewport
- **THEN** the rail and tint also cover the remaining empty viewport rows without changing narrative text or reading position

#### Scenario: Visible loading ends
- **WHEN** the visible restoration, review, or explanation enters Ready, Failed, Cancelled, or Stale, or its reader closes
- **THEN** its loading decorations and cursor-line freeze state are cleared
- **AND** unrelated ongoing work can retain its own header activity indication without decorating idle content

## ADDED Requirements

### Requirement: Continuous busy header indication

Every user-visible busy phase SHALL show an animated spinner in the explanation header, independent of focus, reader mode, or cached content. This includes saved-result checks, collection, cache lookup, external-agent work, review processing, and result validation. Background work SHALL remain identified as background work. Idle and terminal states SHALL not imply activity unless separate owned work remains busy. The editor statusline and request-state integration SHALL remain unchanged.

#### Scenario: Busy phases share header behavior
- **WHEN** an explanation or review is collecting, building a prompt, checking cache, requesting or processing agent output, planning, annotating, reducing, synthesizing, or checking result context
- **THEN** its header spinner advances throughout that phase
- **AND** it shows the actual phase rather than fabricated progress

#### Scenario: Saved-result checks are busy without inference
- **WHEN** the pane shows Checking saved explanations or Checking saved review
- **THEN** the header spinner animates until that check completes or is retired
- **AND** the spinner does not imply that an external agent was invoked

#### Scenario: Focused and expanded readers stay visibly busy
- **WHEN** the user focuses File overview, Review, or expanded detail while owned work remains busy
- **THEN** the header spinner continues advancing without collapsing detail, replacing content, moving either viewport, or stealing focus
- **AND** changing focus does not suppress or restart the busy indication

#### Scenario: Narrow header retains activity when it fits
- **WHEN** a busy header cannot fit its full descriptions but has room for its essential mode/count, Auto when enabled, spinner, and abbreviated phase
- **THEN** those elements remain visible ahead of the brand, legend, hints, progress bar, and background descriptions
- **AND** annotation retains its percentage when the compact phase fits alongside the spinner
- **AND** widths too small for all essential elements retain the existing mode/count/Auto priorities without overflowing or inserting header text into content

#### Scenario: Busy work belongs to another target
- **WHEN** accepted File content is visible while another file or a whole review is running
- **THEN** its header shows the spinner with background-work identification rather than claiming the visible accepted content is being regenerated
- **AND** another target's ranges are not applied to the visible body

#### Scenario: All owned activity stops
- **WHEN** no visible or background busy work remains after completion, failure, cancellation, staleness, or closure
- **THEN** the spinner stops and no late timer callback restores an obsolete busy indication
- **AND** the editor's statusline and undecorated request-state value retain their existing meanings
