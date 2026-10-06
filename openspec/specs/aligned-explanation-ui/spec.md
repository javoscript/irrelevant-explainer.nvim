# aligned-explanation-ui Specification

## Purpose

Keep concise explanations beside their corresponding source display rows, with synchronized navigation and full detail available without disturbing code layout.

## Requirements

### Requirement: Aligned annotation pane

The plugin SHALL open a read-only explanation pane at the far right of the tab, outside both diff sources. The collapsed pane SHALL preserve one logical row per followed source line, including blank rows, with additional rows allowed for exhausted overlaps. Summaries SHALL be visibly truncated rather than wrapped; original anchor labels SHALL remain attached to their notes.

#### Scenario: Sparse notes
- **WHEN** notes target source lines 40, 43, and 46
- **THEN** the pane leaves intervening rows blank and does not compress the notes into a continuous list

#### Scenario: Narrow pane
- **WHEN** a summary is wider than the explanation pane
- **THEN** the summary is truncated with an expansion indicator and subsequent notes retain their row positions

#### Scenario: Request from the old diff side
- **WHEN** explanation is requested from the left old-side window in Diffview
- **THEN** the pane opens beyond the new-side window, not between old and new

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

#### Scenario: Open or close a source fold
- **WHEN** the user changes a fold without moving the cursor or scrolling
- **THEN** the explanation projection updates to the new visible geometry, including folds whose starts have moved above the viewport

#### Scenario: Several changed hunks
- **WHEN** a diff contains multiple separated hunks and collapsed intervening context
- **THEN** each summary follows its own native comparison coordinate, including unequal old/new lengths and filler at EOF

### Requirement: Synchronized navigation

Cursor and viewport actions in either source or the collapsed explanation SHALL synchronize corresponding positions in both directions. Both old and new diff sources SHALL drive the overview. Synchronization SHALL preserve source columns/options and existing diff bindings, avoid feedback loops, and not steal focus. Overflow rows SHALL target their original source anchors rather than their presentation line numbers.

#### Scenario: Scroll from the source
- **WHEN** the user scrolls the source by a viewport, including through folded or wrapped content
- **THEN** the note pane updates to the same visible source rows

#### Scenario: Scroll from the explanation
- **WHEN** the user scrolls within the explanation pane
- **THEN** the paired source view moves to the corresponding position and annotation alignment remains intact

#### Scenario: Ordinary cursor and viewport positioning
- **WHEN** the user uses j/k, other native cursor motions, zz/zt/zb, page or half-page scrolling, or mouse scrolling in an overview/source window
- **THEN** the paired overview and source positions follow, within native buffer limits, even on blank or pending explanation rows

#### Scenario: Traverse a diff insertion or deletion
- **WHEN** j/k in the explanation reaches comparison rows with no real line on the followed side
- **THEN** movement uses the side that owns real code instead of skipping the changed region, and closed folds count as one navigation stop

### Requirement: In-pane detail

Enter or K SHALL toggle already-returned detail inside the explanation pane, without a popup or another AI call. Expansion SHALL retain the summary position when space permits and preserve dimmed neighboring notes above and below. Detail SHALL show prose, intent basis, source path and range controls, but no generated context warning or separate Evidence/Anchors sections. Expansion alone SHALL not move code.

#### Scenario: Expand and close detail
- **WHEN** the user opens a truncated note's detail and then closes it
- **THEN** the full explanation is readable and both paired panes retain their previous positions and alignment

#### Scenario: Several notes share a display row
- **WHEN** separate valid notes project to one folded or shared diff row
- **THEN** the row indicates combined detail and expansion exposes each note with its original source anchors

#### Scenario: Long detail beside neighboring notes
- **WHEN** expanded prose would cover a following summary
- **THEN** that summary remains visible after the card instead of disappearing, and surrounding summaries are display-only context rather than Markdown paragraphs

#### Scenario: Expansion near the viewport bottom
- **WHEN** the selected summary is too low to expose its first detail line
- **THEN** leading explanation context is trimmed enough to show the first body line without moving source code

#### Scenario: Stable horizontal position
- **WHEN** a note expands or collapses
- **THEN** both modes retain the same gutter and one-space left padding, and no neighboring summary shifts sideways

#### Scenario: Compact detail metadata
- **WHEN** a note expands
- **THEN** its intent-basis metadata follows the summary header without an intervening empty row

#### Scenario: Tab is not expansion
- **WHEN** the user presses Tab in either code or diff explanation mode
- **THEN** Explainr does not use it as an expand/collapse mapping; diff mode can pass it to configured Diffview navigation

### Requirement: Separate overlapping summaries

Overlapping summaries SHALL use separate available rows within their anchors, reserving every primary note position first. Equal positions SHALL prioritize overview, narrower range, documented/inferred/unknown intent, then original result order. Exhausted ranges SHALL spill into unused cursor-addressable annotation rows below, adding rows at EOF when needed, without changing anchors or source geometry.

#### Scenario: Narrow and broad notes overlap
- **WHEN** notes start at line 2 with ranges 2–3 and 2–6, and another primary note starts at line 3
- **THEN** the narrower note occupies line 2, the primary stays on line 3, and the broader note uses line 4 with its original 2–6 label

#### Scenario: One-line file has two explanations
- **WHEN** an overview and a change note both reference the only source line
- **THEN** they occupy two independently selectable explanation rows with a range beside each summary, and both synchronize to source line 1

#### Scenario: Stable allocation
- **WHEN** the pane is resized or rendered again with the same notes
- **THEN** sorting and row placement remain deterministic and do not join exhausted overlaps with horizontal separators

### Requirement: Explanation entry navigation

n SHALL select the next explanation and p/N the previous one in displayed order, with counts clamped at either edge and no wrapping. Destinations SHALL be centered with native zz within viewport limits. Navigation while expanded SHALL retain detail mode, synchronize the selected source anchor and both diff sides, and make collapse return to that entry, not the original expansion entry point.

#### Scenario: Count reaches the end
- **WHEN** a counted next action exceeds the remaining entries
- **THEN** navigation stops on the last entry, and another next action does not change detail or restart inference

#### Scenario: Navigate and collapse
- **WHEN** the user expands the first note, navigates to the second, and presses Enter, K, q or Esc
- **THEN** the overview cursor remains at the second summary with the corresponding centered source position

#### Scenario: Statusline stability during expanded navigation
- **WHEN** n/p/N selects another expanded entry
- **THEN** detail updates in the same reading buffer without switching through the overview or reattaching it as a new buffer

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits.

#### Scenario: Leave the expanded range
- **WHEN** the cursor moves into surrounding context outside the current anchors
- **THEN** detail collapses and the overview/source cursor maps to that destination rather than jumping back to the summary

#### Scenario: Read a long paragraph
- **WHEN** the cursor moves within prose taller than its source anchor
- **THEN** all prose remains reachable and paragraph line numbers do not change the source anchor

#### Scenario: Scroll one line with detail open
- **WHEN** Ctrl-e/Ctrl-y, with or without a count, scrolls the explanation or either diff source
- **THEN** all paired viewports scroll by the corresponding display-row distance, accounting for folds, wraps and filler

#### Scenario: Native expanded viewport action
- **WHEN** zz/zt/zb or another motion changes the expanded viewport
- **THEN** source viewports follow the displayed-row movement without treating Markdown rows as source lines or collapsing solely because a source scrolled

### Requirement: Focus and range styling

Focused collapsed and expanded notes SHALL emphasize their full anchor ranges and dim surrounding explanation/source text. Expanded tint and rails SHALL cover at least the visible anchored extent and all prose, not merely its text height. Source styling SHALL use muted gutter markers and outside-anchor foreground dimming, preserving anchored syntax, Git backgrounds and existing signs without underlining code.

#### Scenario: Short detail covers a long range
- **WHEN** an explanation is shorter than its visible anchor span
- **THEN** navigable highlighted continuation extends through the range, including anchored context before a changed-line summary and after neighboring notes

#### Scenario: Focus in a two-sided diff
- **WHEN** a note has old/new anchors, or only an old anchor
- **THEN** both sources dim outside their respective anchors; a side without an anchor dims entirely, while native diff foregrounds and higher-priority Git/diagnostic signs retain precedence

#### Scenario: Theme-derived neutral tint
- **WHEN** focused detail is displayed in a dark or light colorscheme
- **THEN** its subtle neutral surface derives from the theme's CursorLine background, with NormalFloat/normal-text fallbacks and user highlight overrides, while the gutter and left padding remain untinted

#### Scenario: Focus leaves an explanation
- **WHEN** collapsed focus moves to a blank row or another window, or notes become stale or close
- **THEN** temporary focus styling is cleared; explicit collapse otherwise retains focus on the current summary

### Requirement: Optional Markdown rendering

The plugin SHALL optionally use installed render-markdown.nvim for inline code and fenced Markdown detail, without resetting user setup or unrelated Markdown buffers. Missing renderer APIs or parsers SHALL leave readable native semantic styling. Collapsed summaries SHALL remain single-line plain text with unconcealed range and expansion controls.

#### Scenario: Detail contains code
- **WHEN** returned detail contains backtick inline code and a language-tagged fenced snippet
- **THEN** optional rendering formats them, retains code-block styling inside the focus surface, and keeps the range and [+]/[−] controls readable

#### Scenario: Renderer unavailable
- **WHEN** the optional renderer or its Markdown parser is missing
- **THEN** explanations and expansion remain usable without a dependency error or changes to user renderer configuration

### Requirement: Scoped animated loading

All active and queued request ranges SHALL receive a steady faint full-width tint with an animated cursor-width gutter rail and a smooth cascading glow. Animation SHALL preserve accepted text and source diff highlights, update only visible decorations, and pause repainting on the focused logical cursor row. It SHALL stop on completion, failure, cancellation or closure and not modify global cursor or terminal redraw options.

#### Scenario: Two hunks are waiting
- **WHEN** one hunk is being explained and another is queued
- **THEN** both matching explanation ranges animate, including wrapped/folded rows and deletion/EOF filler, while accepted notes remain readable

#### Scenario: Snapshot not yet collected
- **WHEN** a diff request begins before exact anchors are available
- **THEN** a file request previews the whole source and a hunk request previews its cursor/native changed region until collected anchors replace the provisional range

#### Scenario: Cursor is on a loading row
- **WHEN** notes have focus during loading
- **THEN** the cursor row and status spinner stop repainting while other requested rails continue; the plugin leaves guicursor and termsync unchanged and documents synchronized terminal output as a flicker dependency

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
- **THEN** its explanation pane, in-pane detail, pending requests, timers and handlers are cleaned up

#### Scenario: Explicit reader close
- **WHEN** the user presses q/Esc in the collapsed overview or invokes ExplainrClose
- **THEN** the owned reader is closed and pending work is cancelled without closing the source; q/Esc in expanded detail instead collapses the current entry

### Requirement: Explanation status and legend

The pane SHALL show request state, explanation count, current/total ordinal when focused, and the D documented / ~ inferred / ? unknown legend, without taking ownership of the editor's statusline. Focused-context status SHALL identify effective radius and omitted-file count only in the overview. File overviews SHALL reserve a separate matched header so status does not cover their line-1 summary.

#### Scenario: Navigation updates the ordinal
- **WHEN** the second of five explanations is focused or expanded
- **THEN** status identifies 2 / 5; folded groups identify their ordinal range, and appending notes updates the total

#### Scenario: Narrow status area
- **WHEN** the pane cannot fit full state/context/legend text
- **THEN** explanation counts remain prioritized and other text is shortened or abbreviated; non-overview fallback status stays on the first displayed row, including virtual filler

#### Scenario: External lualine remains active
- **WHEN** focus, loading, expansion or entry navigation updates Explainr
- **THEN** the user's local/global statusline remains unchanged, with pane state available through vim.b.explainr_status for optional user integration

## Decisions

- Keep the right-side, sparse annotation pane (Option A), not ghost-text-only annotations or a standalone prose reader. Source wraps, folds, comparison membership and text remain authoritative.
- Replace the original floating-detail plan with in-pane expansion so detail never covers the code it explains. Preserve neighboring notes and use explicit expansion rather than automatic expansion on ordinary cursor movement.
- Give overlapping notes separate lines, not a horizontally concatenated fallback. Reserve primary positions first; overflow labels and cursor targets preserve meaning when perfect one-to-one screen alignment is impossible.
- Use theme-derived neutral focus surfaces and gutter rails rather than fixed gray/green blocks or code underlines. Preserve Git backgrounds and signs; do not force source signcolumn settings.
- Replace the traveling loading wave with steady backgrounds and animated gutter rails. Avoid cursor-cell repainting, but do not promise to eliminate terminal flicker when synchronized output is disabled.
- Treat renderer integration as optional compatibility, not a global Markdown setup or statusline replacement. These decisions supersede the UI assumptions in the archived initial design.
