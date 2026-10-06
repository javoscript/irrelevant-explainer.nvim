# Spec Delta

## REMOVED Requirements

### Requirement: Optional Markdown rendering

**Reason**: Renderer-driven concealment and decoration introduce display geometry changes that are unnecessary for the aligned reader. Syntax highlighting provides structure without this integration.

**Migration**: Explainr no longer invokes render-markdown.nvim for overview or detail. Keep Markdown explanation content and use optional syntax highlighting with visible markers instead. Existing renderer setup and unrelated Markdown buffers remain untouched.

## ADDED Requirements

### Requirement: Renderer-free Markdown highlighting

Overview and detail buffers SHALL use the `explainr` filetype and remain usable without optional parsers. When available, Markdown syntax highlighting SHALL style detail without hiding Markdown markers or adding renderer layout decorations. Explainr SHALL NOT invoke or configure a Markdown renderer. Existing semantic styling, range controls, and single-line collapsed summaries SHALL remain readable.

#### Scenario: Markdown detail with installed parsers
- **WHEN** detail contains headings, emphasis, inline code, and a language-tagged fenced snippet with the corresponding syntax parsers available
- **THEN** its Markdown structure and fenced language receive syntax highlighting while backticks, emphasis delimiters, heading markers, and code fences remain visible
- **AND** the explanation text, including quotes and backslashes, is preserved without Markdown-to-plain-text conversion

#### Scenario: Missing syntax support
- **WHEN** Markdown, inline Markdown, or a fenced language parser is unavailable
- **THEN** opening and reading detail remains usable without a dependency error or automatic parser installation
- **AND** available syntax highlighting and Explainr's semantic summary, metadata, focus tint, gutter, and range controls remain usable without requiring rich highlighting in unsupported regions

#### Scenario: Renderer installed for ordinary Markdown
- **WHEN** render-markdown.nvim is installed and configured to render ordinary Markdown buffers
- **THEN** opening, navigating, resizing, and closing Explainr neither invokes its renderer APIs nor changes its user configuration
- **AND** ordinary Markdown buffers retain their existing filetypes and renderer behavior, while Explainr's buffers use `explainr`

#### Scenario: Predictable wrapping and lifecycle
- **WHEN** a long explanation is opened, traversed, resized, replaced through entry navigation, and collapsed
- **THEN** detail wraps natively with Markdown markers visible throughout, and syntax highlighting alone adds no display rows or concealed text
- **AND** collapse restores the unwrapped aligned overview, preserving existing source-aligned cursor and viewport behavior

### Requirement: Expanded display-row navigation

Normal-mode j/k in expanded detail SHALL move by displayed row, with counts using the same unit. At the first displayed segment of the summary on the top content-screen edge, k SHALL retain the existing counted upward-source-scroll action. Other movement SHALL retain existing anchor-bounded synchronization and outside-context collapse. Collapsed and source-buffer mappings SHALL remain unchanged.

#### Scenario: Move inside a wrapped paragraph
- **WHEN** one paragraph occupies at least four displayed rows and j is pressed on its first displayed row
- **THEN** the cursor moves to the second displayed row of that same buffer line rather than the next paragraph
- **AND** k returns to the preceding displayed row and source selection follows the actual content-screen row within existing anchor bounds

#### Scenario: Counted motion crosses a paragraph boundary
- **WHEN** the cursor is on the first displayed row of a four-row paragraph followed by a blank line and another paragraph, and 4j is pressed
- **THEN** the cursor lands on the blank line, not four buffer lines below
- **AND** 4k returns to the first displayed row, subject to native limits and existing outside-context collapse

#### Scenario: Wrapped summary is not an early scroll trigger
- **WHEN** the cursor is on a later displayed segment of a wrapped summary and k is pressed
- **THEN** it moves to the preceding displayed segment rather than invoking the top-edge upward-source-scroll shortcut
- **AND** this remains true when the later segment is the first visible screen row because earlier segments are scrolled out

#### Scenario: Top-edge summary retains backward scrolling
- **WHEN** the cursor is on the first displayed segment of the expanded summary at the top content-screen edge and k or a counted k is pressed
- **THEN** paired sources scroll upward by the requested display-row count through the existing reading-scroll behavior, bounded by native limits
- **AND** detail stays selected without entering stale leading context, with source cursor selection preserving the existing completed-scroll contract

#### Scenario: Mapping isolation and ordinary motions
- **WHEN** expanded j/k is used with global j/k remappings installed
- **THEN** Explainr's normal-mode buffer-local mappings provide consistent display-row movement in both directions without invoking those global mappings
- **AND** native gj/gk, other ordinary cursor motions, collapsed diff navigation, source-buffer mappings, and global mappings remain unchanged

#### Scenario: Synchronization settles after visual movement
- **WHEN** expanded j/k crosses a viewport edge beside wrapped, folded, or deleted source code
- **THEN** existing displayed-row viewport forwarding and real-source target selection apply to the final reading position
- **AND** repeated cursor, scroll, idle, and redraw events do not replay the movement; current-position collapse retains the resulting source-aligned destination
