# Spec Delta

## ADDED Requirements

### Requirement: Renamed public reader integrations

Reader integrations SHALL use the `IrrelevantExplainer` highlight prefix and `vim.b.irrelevant_explainer_status` for the existing request-state string. Visible branding SHALL read Irrelevant Explainer where space permits; mode, counts, Auto, and activity SHALL keep their existing priorities over branding. The rename SHALL NOT alter source options, alignment, focus, or navigation, or install legacy integration aliases.

#### Scenario: Theme and statusline use the new identity
- **WHEN** a user overrides IrrelevantExplainer semantic highlights and reads vim.b.irrelevant_explainer_status
- **THEN** the reader respects those overrides and exposes its existing request-state meaning without taking over the user's statusline
- **AND** migration instructions explain replacing the former Explainr highlight prefix and explainr_status variable

#### Scenario: Full brand does not fit
- **WHEN** a narrow pane has room for its essential mode, counts, Auto, and activity but not the full brand
- **THEN** the brand is omitted or shortened before those essential elements and no header text enters content rows or overflows the pane

## MODIFIED Requirements

### Requirement: Renderer-free Markdown highlighting

Overview and detail buffers SHALL use the `irrelevant_explainer` filetype and remain usable without optional parsers. When available, Markdown syntax highlighting SHALL style detail without hiding Markdown markers or adding renderer layout decorations. Irrelevant Explainer SHALL NOT invoke or configure a Markdown renderer. Existing semantic styling, range controls, and single-line collapsed summaries SHALL remain readable.

#### Scenario: Markdown detail with installed parsers
- **WHEN** detail contains headings, emphasis, inline code, and a language-tagged fenced snippet with the corresponding syntax parsers available
- **THEN** its Markdown structure and fenced language receive syntax highlighting while backticks, emphasis delimiters, heading markers, and code fences remain visible
- **AND** the explanation text, including quotes and backslashes, is preserved without Markdown-to-plain-text conversion

#### Scenario: Missing syntax support
- **WHEN** Markdown, inline Markdown, or a fenced language parser is unavailable
- **THEN** opening and reading detail remains usable without a dependency error or automatic parser installation
- **AND** available syntax highlighting and Irrelevant Explainer's semantic summary, metadata, focus tint, gutter, and range controls remain usable without requiring rich highlighting in unsupported regions

#### Scenario: Renderer installed for ordinary Markdown
- **WHEN** render-markdown.nvim is installed and configured to render ordinary Markdown buffers
- **THEN** opening, navigating, resizing, and closing Irrelevant Explainer neither invokes its renderer APIs nor changes its user configuration
- **AND** ordinary Markdown buffers retain their existing filetypes and renderer behavior, while Irrelevant Explainer's buffers use `irrelevant_explainer`

#### Scenario: Predictable wrapping and lifecycle
- **WHEN** a long explanation is opened, traversed, resized, replaced through entry navigation, and collapsed
- **THEN** detail wraps natively with Markdown markers visible throughout, and syntax highlighting alone adds no display rows or concealed text
- **AND** collapse restores the unwrapped aligned overview, preserving existing source-aligned cursor and viewport behavior

### Requirement: State-independent header colors

Header text SHALL use stable semantic colors across request states and detail modes. Visible `Irrelevant Explainer` branding SHALL use the theme's information accent by default; counts, spinner, state, separators, descriptions, and navigation hints SHALL be muted. Legend symbols D, ~, and ? SHALL use the same documented, inferred, and unknown highlight groups as explanation items. User highlight overrides SHALL be respected.

#### Scenario: Loading and ready share the same palette
- **WHEN** a header transitions from pending to ready, failed, stale, or cancelled
- **THEN** the title remains accent-colored and other non-marker text remains muted
- **AND** state is distinguished by its text rather than by recoloring the header

#### Scenario: Legend matches explanation markers
- **WHEN** the overview header shows its full or abbreviated intent legend
- **THEN** D uses the documented-item highlight, ~ uses the inferred-item highlight, and ? uses the unknown-item highlight
- **AND** adjacent descriptions and separators remain muted rather than inheriting marker colors

#### Scenario: Expanded header and custom theme
- **WHEN** detail is shown under a theme with customized IrrelevantExplainer semantic highlights
- **THEN** visible title and muted header text use those overrides without changing color when focus or the selected entry changes

#### Scenario: Literal status text
- **WHEN** request state or focused-context text contains a percent sign or multibyte characters
- **THEN** it appears as literal, width-bounded text without introducing header formatting or breaking semantic highlighting

### Requirement: Display-only narrative access

Irrelevant Explainer SHALL expose `:IrrelevantExplainerReview`, `require("irrelevant_explainer").review()`, and a pane-local remappable `<Plug>(IrrelevantExplainerReview)` action to select Review without inference. They SHALL show a retained narrative or an explicit pending, empty, failed, or stale state for the current comparison. No global default mapping SHALL be installed. Reopening the same narrative SHALL preserve its reading position.

#### Scenario: Return to the narrative
- **WHEN** the user scrolls Review, reads two files, and invokes IrrelevantExplainerReview
- **THEN** the same narrative returns at its saved reading position without another request or selecting another Diffview file

#### Scenario: Narrative has not been generated
- **WHEN** IrrelevantExplainerReview is invoked in a supported comparison without a retained or pending review
- **THEN** the reader shows an empty Review state directing the user to IrrelevantExplainer review
- **AND** opening that state does not generate explanations, including with Auto enabled

#### Scenario: No supported comparison
- **WHEN** display-only Review access is invoked outside a supported Diffview comparison
- **THEN** it reports the missing comparison without inference, opening Diffview, or changing a code explanation reader

#### Scenario: Review generation begins
- **WHEN** IrrelevantExplainer review is explicitly requested in a coherent comparison
- **THEN** the pane selects Review pending mode without stealing focus and preserves any still-fresh prior narrative while waiting
- **AND** a replacement narrative starts at its beginning only if Review is still selected when installed

### Requirement: Comparison narrative reading mode

Diff readers SHALL offer Review and File modes in the same right-hand pane. Review SHALL display the whole-change narrative as read-only, independently scrollable Markdown, without source alignment, source focus decorations, or a floating window. File SHALL retain aligned overview and expanded detail behavior. Review SHALL use the irrelevant_explainer filetype, optional syntax highlighting, visible Markdown markers, and native wrapping without a renderer dependency.

#### Scenario: Read across files without displacing code
- **WHEN** Review is selected after a review response is accepted
- **THEN** its title, narrative sections, intent labels, and file references appear in the existing pane
- **AND** no narrative rows are inserted above the aligned File notes or into source buffers

#### Scenario: Independent narrative scrolling
- **WHEN** the user moves or scrolls through a long Review narrative, including wrapped paragraphs
- **THEN** all narrative content remains reachable without moving either source cursor or viewport
- **AND** source scrolling does not scroll or collapse Review; native old/new diff synchronization remains active

#### Scenario: Enter Review from expanded file detail
- **WHEN** the user switches from expanded File detail to Review
- **THEN** file-note dimming, anchor rails, and source-linked detail motion are removed from the active reader
- **AND** returning to File restores aligned overview without changing source wrapping, folds, gutters, or diff membership

#### Scenario: No Markdown parser
- **WHEN** optional syntax parsers are unavailable
- **THEN** Review remains readable with literal Markdown markers and no automatic parser installation or renderer invocation

### Requirement: Nondisruptive live mode indication

Toggling automation SHALL immediately update all open diff-pane headers, including background tabs and expanded detail. Header updates SHALL preserve request state, accepted notes, active jobs, selected explanation, detail buffer, cursors, viewports, and focus. The editor's local/global statusline and the existing request-state meaning of `vim.b.irrelevant_explainer_status` SHALL remain unchanged.

#### Scenario: Toggle while reading expanded detail
- **WHEN** the user toggles automation with a diff explanation expanded and its prose scrolled
- **THEN** `Auto` appears or disappears immediately without collapsing detail, replacing its buffer, moving the cursor or viewport, changing the selected note, or starting inference

#### Scenario: Multiple open tabs
- **WHEN** the user toggles automation while multiple tabs contain open diff explanation panes
- **THEN** every owned diff-pane header reflects the new setting without switching tabs or windows
- **AND** any code-pane header remains without an automatic-mode indicator

#### Scenario: Existing status integrations
- **WHEN** automation is toggled with a user statusline or lualine active
- **THEN** the editor statusline remains unchanged and `vim.b.irrelevant_explainer_status` continues to expose the existing request-state string rather than an indicator-decorated replacement
