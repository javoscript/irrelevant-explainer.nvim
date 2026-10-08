## MODIFIED Requirements

### Requirement: Display-only narrative access

Explainr SHALL expose `:ExplainrReview`, `require("explainr").review()`, and a pane-local remappable `<Plug>(ExplainrReview)` action to select Review without inference. They SHALL show a retained narrative or an explicit pending, empty, failed, or stale state for the current comparison. No global default mapping SHALL be installed. Reopening the same narrative SHALL preserve its reading position.

#### Scenario: Return to the narrative
- **WHEN** the user scrolls Review, reads two files, and invokes ExplainrReview
- **THEN** the same narrative returns at its saved reading position without another request or selecting another Diffview file

#### Scenario: Narrative has not been generated
- **WHEN** ExplainrReview is invoked in a supported comparison without a retained or pending review
- **THEN** the reader shows an empty Review state directing the user to Explainr review
- **AND** opening that state does not generate explanations, including with Auto enabled

#### Scenario: No supported comparison
- **WHEN** display-only Review access is invoked outside a supported Diffview comparison
- **THEN** it reports the missing comparison without inference, opening Diffview, or changing a code explanation reader

#### Scenario: Review generation begins
- **WHEN** Explainr review is explicitly requested in a coherent comparison
- **THEN** the pane selects Review pending mode without stealing focus and preserves any still-fresh prior narrative while waiting
- **AND** a replacement narrative starts at its beginning only if Review is still selected when installed
