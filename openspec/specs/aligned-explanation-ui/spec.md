# aligned-explanation-ui Specification

## Purpose

Keep concise explanations beside their corresponding source display rows, with synchronized navigation and full detail available without disturbing code layout.

## Requirements

### Requirement: Aligned annotation pane

The plugin SHALL open a read-only explanation pane at the far right of the tab, outside both diff sources. In code mode and diff File mode, the collapsed pane SHALL preserve one logical row per followed source line, including blank rows, with additional rows allowed for exhausted overlaps. Summaries SHALL be visibly truncated rather than wrapped; original anchor labels SHALL remain attached to their notes. Diff Review mode SHALL instead use the independent narrative reading contract.

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

Enter or K SHALL toggle already-returned detail inside the explanation pane, without a detail popup or another AI call. Expansion SHALL retain the summary position when space permits and preserve dimmed neighboring notes above and below, including when triggered elsewhere in its anchors. Detail SHALL show prose, intent basis, source path and range controls, but no generated context warning or separate Evidence/Anchors sections. Expansion alone SHALL not move code. An ambiguity chooser SHALL select a note without replacing in-pane detail.

#### Scenario: Expand and close detail
- **WHEN** the user opens a truncated note's detail and then closes it without moving or scrolling
- **THEN** the full explanation is readable and the source position and paired alignment are preserved
- **AND** collapse resolves the current source-aligned position rather than restoring a saved summary or invocation row

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

#### Scenario: Expansion from a continuation row
- **WHEN** a note's summary is at line 20 and the user presses Enter or K at a summary-free row corresponding to line 31 within its 20–40 anchors
- **THEN** its detail opens beneath its existing summary when visible space permits, using the existing off-screen fallback otherwise
- **AND** opening does not move the source cursor from line 31 or reposition the source viewport

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

n SHALL select the next explanation and p/N the previous one in displayed order, with counts clamped at either edge and no wrapping. Destinations SHALL be centered with native zz within viewport limits. Navigation while expanded SHALL retain detail mode and synchronize the selected source anchor and both diff sides. Subsequent explicit collapse SHALL retain the current source-aligned position, not restore either the selected entry's summary or the original expansion entry point.

#### Scenario: Count reaches the end
- **WHEN** a counted next action exceeds the remaining entries
- **THEN** navigation stops on the last entry, and another next action does not change detail or restart inference

#### Scenario: Navigate and collapse
- **WHEN** the user expands the first note, navigates to the second, moves to another source-aligned line inside the second note, and presses Enter, K, q or Esc
- **THEN** the overview and source cursors remain at that current line rather than returning to either summary
- **AND** the current source viewport is preserved within native display limits

#### Scenario: Statusline stability during expanded navigation
- **WHEN** n/p/N selects another expanded entry
- **THEN** detail updates in the same reading buffer without switching through the overview or reattaching it as a new buffer

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Explanation-driven viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits. Source-driven scrolling SHALL preserve sticky detail visibility rather than require equal explanation viewport movement. Completed explanation-driven scrolls SHALL synchronize the source cursor to the reader's final source-aligned target without adding viewport movement; anchored context SHALL retain its exact source target and prose SHALL use visible-anchor visual-row selection. Expanded Ctrl-e/Ctrl-y actions SHALL settle without displaying an intermediate scroll that is subsequently undone by card-placement reconciliation. A further reader Ctrl-y blocked solely by a fitting card's bottom placement limit SHALL enter the source-backed display row immediately above the card, collapsing only when that destination is outside its active anchors.

#### Scenario: Leave the expanded range
- **WHEN** the cursor moves into surrounding context outside the current anchors
- **THEN** detail collapses and the overview/source cursor maps to that destination rather than jumping back to the summary

#### Scenario: Read a long paragraph
- **WHEN** the cursor moves within prose taller than its source anchor
- **THEN** all prose remains reachable without collapsing or auto-expanding another note
- **AND** prose-driven source cursor synchronization uses anchored display positions rather than paragraph buffer line numbers

#### Scenario: Scroll one line with detail open
- **WHEN** Ctrl-e/Ctrl-y, with or without a count, scrolls the expanded explanation
- **THEN** paired sources follow its actual viewport movement by the corresponding display-row distance, accounting for folds, wraps and filler within native limits
- **AND** this behavior remains available while the card is pinned, with the bottom placement escape defined below taking precedence when applicable
- **AND** the source cursor selects the reader's final source-aligned target after scrolling, even when the reader cursor's buffer line and column remain unchanged

#### Scenario: Scroll upward at the expanded reader's upper limit
- **WHEN** Ctrl-y is pressed with no earlier explanation buffer rows, or k is pressed on the expanded summary at the top content-screen edge
- **THEN** paired sources scroll upward by the requested count of native display rows while detail remains selected and available, except when a subsequent Ctrl-y step qualifies for the bottom placement escape
- **AND** stale leading context does not collapse detail or add a source jump, and source beginning-of-buffer limits are respected
- **AND** source cursor selection uses the final pinned or released reader placement rather than the position before scrolling

#### Scenario: Native expanded viewport action
- **WHEN** zz/zt/zb or another motion changes the expanded viewport
- **THEN** source viewports follow the displayed-row movement without treating Markdown rows as source lines or collapsing solely because a source scrolled
- **AND** sticky placement does not undo user-driven prose scrolling
- **AND** source cursor selection resolves against the final viewport geometry without adding another scroll

#### Scenario: Source scrolloff margins
- **WHEN** expanded scrolling occurs with inherited or window-local source scrolloff, including different margins on the two diff sides
- **THEN** synchronization uses the actual displayed-row movement without adding or losing distance to a pending cursor-margin correction
- **AND** the original global and local scrolloff values are retained, source-driven motion stays native, and repeated redraw or synchronization events do not introduce drift
- **AND** with an eligible reader target, the final source cursor selects that target rather than retaining a temporary margin-normalization position

#### Scenario: Source-driven scroll with detail open
- **WHEN** a keyboard viewport action, cursor motion that scrolls, or mouse wheel moves either source while detail is expanded
- **THEN** the paired sources retain native synchronization and the selected explanation follows its natural position only within sticky viewport bounds
- **AND** pinning does not scroll sources again, steal focus, or apply prose cursor mapping to an inactive explanation cursor
- **AND** source-driven scrolling does not trigger the reader's bottom placement escape

#### Scenario: Counted scrolling relocates the reader cursor into anchored continuation
- **WHEN** a counted Ctrl-e/Ctrl-y scroll forces the reader cursor onto a different real context row inside the active anchors
- **THEN** source cursor selection retains that row's exact source position, including folded or deleted code, after the scroll completes
- **AND** detail remains selected, explanation focus is retained, and source viewports receive no extra movement from selection

#### Scenario: Scroll reaches a native limit without movement
- **WHEN** Ctrl-e/Ctrl-y cannot move the reader or sources because the applicable native limits have been reached, rather than solely because a fitting card has reached its bottom placement limit
- **THEN** the action does not relocate cursors, replay an earlier scroll, or change the selected detail
- **AND** the action does not flash a temporary displaced card or invent a context destination beyond the file boundary

#### Scenario: Repeated events after a completed scroll
- **WHEN** cursor, scroll, idle, or redraw events occur after an explanation-driven scroll and final cursor selection have settled
- **THEN** both source cursors and source/reader viewports retain their settled positions without replaying selection or scrolling
- **AND** explicit collapse retains the current source-aligned destination rather than a temporary scrolloff-normalization position

#### Scenario: Ctrl-e at the top edge does not flash a correction
- **WHEN** a fitting expanded card is at the top content edge and Ctrl-e is pressed once or repeatedly
- **THEN** the reader does not display the card scrolled above the edge and then restored by a later placement correction
- **AND** any valid paired scrolling and final source selection happen once, while a genuine native no-op leaves the settled state unchanged
- **AND** the action does not collapse detail solely because the card touches the top edge

#### Scenario: Reach the bottom placement edge without leaving detail
- **WHEN** reader Ctrl-y moves a fitting expanded card to the last position where its full content fits
- **THEN** detail remains expanded and the action does not move the cursor into outside context merely because the edge was reached

#### Scenario: Further Ctrl-y escapes a placement-blocked card
- **WHEN** the cursor is within a fitting card at its bottom placement limit, the next reader Ctrl-y step would be blocked solely by keeping the card fully visible, and the source-backed display row immediately above the card is outside the active anchors
- **THEN** the cursor enters that context row and detail collapses at its corresponding source destination
- **AND** the explanation pane retains focus, both diff sources remain synchronized, and no neighboring note is automatically expanded
- **AND** collapse preserves the current source viewport within native visibility limits rather than restoring the summary or expansion-time view

#### Scenario: Preceding context is still anchored
- **WHEN** the bottom placement escape from within the card targets a source-backed row inside the active anchors
- **THEN** the cursor selects that exact context destination and detail remains expanded
- **AND** the action does not skip over anchored rows to force a collapse
- **AND** subsequent context navigation does not repeatedly force the cursor back to that escape row

#### Scenario: Count crosses the placement boundary
- **WHEN** a counted reader Ctrl-y reaches the bottom placement edge with additional steps remaining
- **THEN** preceding steps scroll normally and the first placement-blocked step performs the context escape exactly once
- **AND** that command stops at the escape destination without applying leftover steps or replaying the original count after collapse
- **AND** a count ending exactly at the placement edge retains expanded detail without escaping

#### Scenario: Escape resolves wrapped folded and deleted context
- **WHEN** the preceding source-backed display row is a wrapped segment, a closed fold, or old-side deleted code represented by filler on the followed side
- **THEN** the escape resolves that row's actual source owner and line, retaining fold state and native diff alignment
- **AND** the destination is not calculated by subtracting one from a Markdown buffer line or by treating filler as new-side code

#### Scenario: Viewport-filling and long prose remain readable
- **WHEN** a card is taller than the content viewport, or a viewport-filling card has no preceding source-backed display row available
- **THEN** the bottom placement escape does not replace ordinary prose scrolling or fabricate a context row
- **AND** all prose remains reachable with the existing paired-scroll and anchor-bounded selection behavior

#### Scenario: Events after a boundary escape are idempotent
- **WHEN** scroll, cursor, idle, or redraw events follow a completed context escape
- **THEN** the destination, focus, detail state, and paired viewports remain unchanged
- **AND** no stale expanded placement reopens detail, restores the old cursor, or applies the escape again

### Requirement: Sticky expanded detail placement

Code-driven scrolling SHALL keep expanded detail inside the explanation content viewport, aligned with its selected summary when space permits and clamped at the top or bottom otherwise. A fitting card SHALL remain fully visible; a taller card SHALL retain a visible reading area. Placement SHALL exclude the persistent header and preserve selection and prose reading position, including when all source anchors leave the screen.

#### Scenario: Natural alignment before an edge
- **WHEN** code scrolls while the expanded card still fits at its summary's natural display position
- **THEN** the card follows that position instead of remaining permanently fixed at the top

#### Scenario: Pin at the top
- **WHEN** scrolling code down would move a short expanded card partly or entirely above the explanation content viewport
- **THEN** the whole card remains visible with its top clamped immediately below the persistent header
- **AND** its original range labels and selected identity remain unchanged

#### Scenario: Pin at the bottom
- **WHEN** scrolling code up would move a short expanded card partly or entirely below the explanation content viewport
- **THEN** the whole card remains visible with its bottom clamped to the content viewport's last row
- **AND** no source viewport adjustment is added to make the card fit

#### Scenario: Return from either edge
- **WHEN** code scrolls back until the expanded card's natural position fits inside the viewport again
- **THEN** the card resumes that aligned position without changing the selected explanation or resetting the reading position

#### Scenario: All source anchors leave the screen
- **WHEN** code scrolls beyond all anchors of the selected explanation
- **THEN** its expanded reading area remains available until explicit collapse, explanation navigation, movement into outside context, or normal pane/result cleanup
- **AND** source-driven scrolling alone neither collapses detail nor expands another explanation

#### Scenario: Detail is taller than the viewport
- **WHEN** an expanded explanation's summary, metadata and prose exceed the available content height and code scrolls
- **THEN** a reading area remains inside the explanation pane and the current prose reading position is preserved
- **AND** the user can still reach every paragraph by scrolling the explanation, with code following that reading scroll
- **AND** visibility of every paragraph or a separately sticky summary is not required

#### Scenario: Preserve a wrapped reading position
- **WHEN** the user is reading a later wrapped segment of a paragraph and then scrolls code enough to pin or unpin the explanation
- **THEN** placement retains that logical reading position rather than jumping to the paragraph start or first detail line

#### Scenario: Neighboring context and range extent
- **WHEN** code scrolls with a short explanation covering a long source range and neighboring notes are available
- **THEN** sticky bounds are based on the explanation card rather than its blank anchored continuation
- **AND** dimmed neighboring context remains available where space permits without displacing the active reading area off-screen or hiding neighboring notes permanently

#### Scenario: Geometry changes while expanded
- **WHEN** a resize, width-dependent wrap, source fold change, or diff-filler update changes display geometry
- **THEN** placement is recomputed within the new content viewport without changing source options, selected identity, or the logical prose reading position
- **AND** repeated synchronization events do not oscillate between aligned and pinned placement

#### Scenario: Existing navigation and cleanup
- **WHEN** the user selects another explanation with n/p/N, collapses detail, changes the diff file, replaces results, or closes a paired window
- **THEN** sticky state is reset or removed through that action's existing lifecycle without leaving stale context, decorations, or viewport synchronization
- **AND** explicit collapse uses the current source-aligned destination rather than replaying a pinning position or expansion-time source view

### Requirement: Expanded prose visual-row synchronization

Explanation-driven movement through expanded summary, metadata and prose SHALL synchronize the source cursor by relative content-screen row after viewport synchronization. Targets SHALL be real anchored source lines, resolving wraps, folds and diff filler. Outside the anchors, the nearest visible anchored position SHALL be used. With no visible anchored target, prose mapping SHALL leave the native source cursor unchanged. Focus and source viewport SHALL be preserved. This selection SHALL also follow completed explanation-driven scrolling, including sticky-edge scrolling that changes the source viewport without moving the reader cursor.

#### Scenario: Move inside prose without scrolling
- **WHEN** an expanded explanation references new-side lines 37–58 and the cursor moves from its summary to prose displayed beside new-side line 42 without changing either viewport
- **THEN** the new-side source cursor moves to line 42 instead of remaining at line 37
- **AND** detail stays expanded and the explanation pane retains focus

#### Scenario: Move across wrapped prose segments
- **WHEN** one paragraph buffer line wraps onto several screen rows beside distinct anchored source lines and the cursor moves to a later wrapped segment
- **THEN** the source cursor follows that segment's relative screen row even though the paragraph buffer line number did not change

#### Scenario: Source geometry differs from prose geometry
- **WHEN** the prose cursor's relative screen row corresponds to a wrapped source line or a closed fold containing anchored code
- **THEN** the target is that source buffer line or the fold start, not a line calculated from the Markdown buffer row
- **AND** wrapping and fold state remain unchanged

#### Scenario: Prose beside old-only deleted code
- **WHEN** the prose cursor sits beside an anchored deleted line represented as filler in the new-side source
- **THEN** the old-side source cursor selects the real deleted line and the paired new-side cursor follows the native comparison coordinate
- **AND** focus remains in the explanation pane and the pane remains outside the diff comparison

#### Scenario: Prose extends beyond visible anchor boundaries
- **WHEN** the prose cursor sits above or below the visible anchored extent, including beside unrelated code or past source EOF
- **THEN** the source cursor selects the nearest visible anchored position rather than unrelated code
- **AND** prose remains readable without collapsing and cursor synchronization does not change the source viewport

#### Scenario: Prose beside a gap between anchors
- **WHEN** an expanded explanation has disjoint visible anchor ranges and the prose cursor sits beside the unanchored gap
- **THEN** the source cursor selects the nearest visible anchored display position, choosing the earlier position for equal distances

#### Scenario: Read beyond off-screen anchors
- **WHEN** scrolling a long explanation takes all its anchored code off-screen
- **THEN** paired viewports retain their native displayed-row scrolling and prose mapping does not snap the source viewport or cursor back to an off-screen anchor
- **AND** detail remains expanded

#### Scenario: Expansion and source-driven motion do not trigger prose mapping
- **WHEN** detail is first opened or the user moves in a paired source window while detail is open
- **THEN** the new prose mapping does not relocate the source cursor to the inactive explanation cursor's screen row
- **AND** expansion alone does not move code and existing source-driven viewport synchronization remains available

#### Scenario: Top-pinned prose cursor stays still while code scrolls
- **WHEN** each source line occupies one display row with no filler, the reader cursor is on the fourth content-screen row of a top-pinned card, visible anchors cover source lines 40–100, the source topline is 70 with scrolloff zero, and Ctrl-y moves that topline to 69 while the reader stays at its upper buffer limit
- **THEN** source cursor selection changes from line 73 to line 72 although the reader cursor stays on the same buffer line and column
- **AND** the source topline remains 69 and detail stays expanded

#### Scenario: Final selection crosses a scrolloff boundary
- **WHEN** an explanation-driven scroll leaves prose beside a visible anchored source line inside the source's effective scrolloff margin
- **THEN** the source cursor selects that anchored line while preserving the completed source viewport and original scrolloff settings
- **AND** repeating the action does not leave the cursor at a viewport-middle normalization position

#### Scenario: Post-scroll prose resolves current geometry and bounds
- **WHEN** an explanation-driven scroll places a wrapped prose segment beside a source wrap, fold, deletion filler, or gap between disjoint anchors
- **THEN** selection uses the segment's final content-screen row and the current source geometry with the existing nearest-visible and earlier-row tie rules
- **AND** neither Markdown buffer line numbers nor pre-scroll source positions determine the result

#### Scenario: Entry initialization and geometry changes are not reading scrolls
- **WHEN** n/p/N initializes another detail entry or resizing, folding, or Markdown reflow changes placement without a user reading action
- **THEN** the resulting events do not apply the reader's inactive prose cursor to source code
- **AND** existing entry selection, native source positions, and logical reading-position preservation remain unchanged

### Requirement: Focus and range styling

Focused collapsed and expanded notes SHALL emphasize their full anchor ranges and dim surrounding explanation/source text. Expanded tint and rails SHALL cover at least the visible anchored extent and all prose, not merely its text height. Source styling SHALL use muted gutter markers and outside-anchor foreground dimming, preserving anchored syntax, Git backgrounds and existing signs without underlining code. Source decorations SHALL be scoped to the captured source windows (both comparison windows in diff mode), not every window displaying the same buffers. Explicit collapse SHALL derive collapsed focus from the destination row without moving to a summary to retain focus.

#### Scenario: Shared-buffer split stays undecorated
- **WHEN** a collapsed summary is focused or its detail is expanded and another split displays the same source buffer
- **THEN** dimming and anchor gutter rails appear only in the captured source window, including when the other split is opened after focus styling is applied
- **AND** the other split retains its normal syntax colors and existing signs without Explainr source decorations

#### Scenario: Shared-buffer tab stays undecorated
- **WHEN** expanded detail is open and the user opens the same source buffer in another tab
- **THEN** the new tab shows neither Explainr source dimming nor anchor gutter rails
- **AND** returning to the original tab retains the expanded explanation and its source decorations until normal focus cleanup

#### Scenario: Short detail covers a long range
- **WHEN** an explanation is shorter than its visible anchor span
- **THEN** navigable highlighted continuation extends through the range, including anchored context before a changed-line summary and after neighboring notes

#### Scenario: Focus in a two-sided diff
- **WHEN** a note has old/new anchors, or only an old anchor
- **THEN** both sources dim outside their respective anchors; a side without an anchor dims entirely, while native diff foregrounds and higher-priority Git/diagnostic signs retain precedence
- **AND** other windows displaying either comparison buffer do not inherit that explanation's source decorations

#### Scenario: Theme-derived neutral tint
- **WHEN** focused detail is displayed in a dark or light colorscheme
- **THEN** its subtle neutral surface derives from the theme's CursorLine background, with NormalFloat/normal-text fallbacks and user highlight overrides, while the gutter and left padding remain untinted

#### Scenario: Focus leaves an explanation
- **WHEN** collapsed focus moves to a blank row or another window, or notes become stale or close
- **THEN** temporary focus styling is cleared

#### Scenario: Collapse onto a blank overview row
- **WHEN** explicit collapse lands on a row without a summary even though an explanation's anchors cover that row
- **THEN** expanded styling is removed and collapsed summary focus is cleared without relocating either cursor

#### Scenario: Collapse onto another summary
- **WHEN** explicit collapse lands on a row displaying another explanation's summary
- **THEN** collapsed focus and its ordinal reflect that row's summary rather than the previously expanded explanation
- **AND** the other explanation is not automatically expanded

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

### Requirement: Scoped animated loading

Active and queued request ranges matching the displayed code or diff File target SHALL receive a steady faint full-width tint with an animated cursor-width gutter rail and a smooth cascading glow. Off-screen requests SHALL use status without misplaced range decorations. A pending Review SHALL animate its own visible narrative viewport, including an empty narrative, independently of source ranges. Animation SHALL preserve accepted text and source diff highlights, update only visible decorations, and pause repainting on the focused logical cursor row. It SHALL stop on completion, failure, cancellation, staleness or closure and not modify global cursor or terminal redraw options.

#### Scenario: Narrative generation is pending
- **WHEN** Review is visible while a whole-review request is pending
- **THEN** the narrative body shows the loading tint and rail without rewriting retained prose or changing its cursor, wrapping or viewport
- **AND** the empty state also animates, leaving source windows unchanged
- **AND** leaving Review clears its decorations; returning resumes them only if the review is still pending

#### Scenario: Two hunks are waiting
- **WHEN** one hunk is being explained and another is queued for the displayed file
- **THEN** both matching explanation ranges animate, including wrapped/folded rows and deletion/EOF filler, while accepted notes remain readable

#### Scenario: Snapshot not yet collected
- **WHEN** a diff request begins before exact anchors are available
- **THEN** a matching displayed file request previews the whole source and a hunk request previews its cursor/native changed region until collected anchors replace the provisional range
- **AND** navigation to a different file removes those provisional decorations rather than transferring them

#### Scenario: Cursor is on a loading row
- **WHEN** notes have focus during loading
- **THEN** the cursor row and status spinner stop repainting while other requested rails continue; the plugin leaves guicursor and termsync unchanged and documents synchronized terminal output as a flicker dependency

### Requirement: Diff isolation

The explanation pane SHALL remain outside the source diff comparison and native bound-window membership. Opening, scrolling, resizing, or closing it SHALL not compare prose against code, disable existing diff synchronization, or leave source window options changed.

#### Scenario: Explanation beside Diffview
- **WHEN** the pane is opened in a synchronized two-way Diffview layout
- **THEN** the source sides remain synchronized and only the original code buffers participate in diff computation

### Requirement: Lifecycle and status

The UI SHALL identify pending, failed, and stale explanation states separately from valid notes in code, diff File, and Review modes. Closing the source/view or explicitly closing explanation SHALL close its pane, detail and narrative, cancel all owned pending work, and remove its event handlers without changing unrelated windows. Ordinary file navigation within the same diff comparison SHALL preserve owned requests and reset only file-specific display state.

#### Scenario: Failure after previous success
- **WHEN** a refresh fails while an older explanation exists
- **THEN** the pane identifies the failure and does not present older notes or a narrative as a successful fresh result

#### Scenario: Source closes
- **WHEN** the paired source window or Diffview view closes
- **THEN** its explanation pane, in-pane detail, narrative buffer, pending requests, timers and handlers are cleaned up
- **AND** late callbacks cannot reopen the reader or install cancelled results

#### Scenario: Explicit reader close
- **WHEN** the user presses q/Esc in the code or diff File collapsed overview, q in Review, or invokes ExplainrClose
- **THEN** the owned reader is closed and pending work is cancelled without closing the source; q/Esc in expanded detail instead collapses the current entry and Esc in Review returns to File

### Requirement: Explanation status and legend

Code and diff File mode SHALL show request state, explanation count, current/total ordinal when focused, and the D documented / ~ inferred / ? unknown legend in a separate matched header, without taking ownership of the editor's statusline. Focused-context status SHALL identify effective radius and omitted-file count only in the File overview. Expanded detail SHALL retain its compact count/navigation header. Review SHALL use comparison status rather than file-note counts.

#### Scenario: Navigation updates the ordinal
- **WHEN** the second of five explanations is focused or expanded
- **THEN** status identifies 2 / 5; folded groups identify their ordinal range, and appending notes updates the total

#### Scenario: Narrow status area
- **WHEN** the code or diff File pane cannot fit full state/context/legend text
- **THEN** explanation counts remain prioritized and other text is shortened or abbreviated within the header
- **AND** status never falls back to a content row, including virtual filler, and visible segments retain their semantic colors

#### Scenario: External lualine remains active
- **WHEN** focus, loading, expansion, Review/File switching or entry navigation updates Explainr
- **THEN** the user's local/global statusline remains unchanged, with pane state available through vim.b.explainr_status for optional user integration

### Requirement: Persistent matched explanation header

The pane SHALL reserve its header above content from opening until closure, independent of results, request state, or detail mode. Paired sources lacking winbars SHALL receive temporary blank matching headers. Existing source headers and user edits SHALL be preserved. Owned placeholders SHALL be restored when sources leave pane ownership or the pane closes. No header SHALL be inserted into buffer content.

#### Scenario: Initial loading without source headers
- **WHEN** a code or diff explanation pane opens before explanations are available and paired sources have no winbars
- **THEN** a separate explanation header and matching blank source headers are present immediately
- **AND** the first visible explanation content row aligns with the followed source row, including wrapping, folds, and diff filler

#### Scenario: Results and terminal states do not move the header
- **WHEN** initial loading completes with or without a file-overview note, or the pane enters refresh, failed, stale, or cancelled state
- **THEN** the header remains above content without adding or removing header rows because of that transition
- **AND** clearing results does not remove the matching source placeholders

#### Scenario: Expand and collapse retain the reserved row
- **WHEN** an explanation is expanded, navigated in detail, and collapsed
- **THEN** the header uses the same reserved screen row throughout
- **AND** expansion alone does not move source code and collapse restores the aligned overview

#### Scenario: Preserve existing headers and restore placeholders
- **WHEN** a pane pairs one source with an existing winbar and another without one, then closes or stops owning a source
- **THEN** existing source header text remains unchanged and owned blank placeholders are restored to their original values
- **AND** a user replacement of a temporary blank header is not overwritten during cleanup

### Requirement: State-independent header colors

Header text SHALL use stable semantic colors across request states and detail modes. Visible `Explainr` text SHALL use the theme's information accent by default; counts, spinner, state, separators, descriptions, and navigation hints SHALL be muted. Legend symbols D, ~, and ? SHALL use the same documented, inferred, and unknown highlight groups as explanation items. User highlight overrides SHALL be respected.

#### Scenario: Loading and ready share the same palette
- **WHEN** a header transitions from pending to ready, failed, stale, or cancelled
- **THEN** the title remains accent-colored and other non-marker text remains muted
- **AND** state is distinguished by its text rather than by recoloring the header

#### Scenario: Legend matches explanation markers
- **WHEN** the overview header shows its full or abbreviated intent legend
- **THEN** D uses the documented-item highlight, ~ uses the inferred-item highlight, and ? uses the unknown-item highlight
- **AND** adjacent descriptions and separators remain muted rather than inheriting marker colors

#### Scenario: Expanded header and custom theme
- **WHEN** detail is shown under a theme with customized Explainr semantic highlights
- **THEN** visible title and muted header text use those overrides without changing color when focus or the selected entry changes

#### Scenario: Literal status text
- **WHEN** request state or focused-context text contains a percent sign or multibyte characters
- **THEN** it appears as literal, width-bounded text without introducing header formatting or breaking semantic highlighting

### Requirement: Anchor-range expansion selection

Enter/K in the collapsed pane SHALL prioritize summaries at the cursor, including folded groups and overflow entries. Otherwise it SHALL select notes whose original anchors cover the source display position. One candidate SHALL open directly; one local candidate SHALL take precedence over covering overviews. Other multi-candidate cases SHALL prompt selection with summaries and original ranges, local candidates first and overviews last.

#### Scenario: Summary takes precedence over overlapping anchors
- **WHEN** a visible summary row also lies within a file overview and another local explanation's anchors
- **THEN** Enter/K expands the displayed summary directly without offering a chooser

#### Scenario: Relocated summary remains directly selectable
- **WHEN** a summary spills outside its anchors, including into an additional annotation row at EOF
- **THEN** Enter/K on that summary still expands its own explanation rather than selecting by the unrelated presentation line

#### Scenario: Only one covering explanation
- **WHEN** the cursor is on a summary-free row at the first, an interior, or the last line of an explanation's anchors and no other candidate covers it
- **THEN** Enter/K expands that explanation directly

#### Scenario: Whole-file overview with one local explanation
- **WHEN** a summary-free row is covered by a whole-file overview and exactly one local explanation
- **THEN** Enter/K expands the local explanation without prompting
- **AND** the overview remains directly accessible from its summary row

#### Scenario: Overview only
- **WHEN** a summary-free row is covered only by a whole-file overview
- **THEN** Enter/K expands the overview directly

#### Scenario: Multiple local explanations
- **WHEN** a summary-free row is covered by a function note for lines 20–40, a validation note for lines 28–32, and an overview for lines 1–100
- **THEN** Enter/K offers both local explanations and the overview with their summaries and original range labels
- **AND** the overview appears after the local explanations, and selecting any candidate expands only that candidate
- **AND** the narrower validation range is not selected automatically

#### Scenario: Chooser cancellation
- **WHEN** the user cancels ambiguity selection
- **THEN** no detail opens and the pane's cursor and source positions remain unchanged by the expansion action

#### Scenario: Selection becomes obsolete
- **WHEN** the pane closes, its result is replaced, or the diff file changes before a pending chooser selection completes
- **THEN** the obsolete selection does not expand a note in the closed or replacement view

#### Scenario: Actual diff anchors precede summary placement
- **WHEN** a local explanation references anchored context before its relocated changed-line summary, or an old-side deletion shown as filler in the followed new side
- **THEN** Enter/K on a summary-free covered display position includes that explanation among the candidates regardless of the summary's placement or followed side

#### Scenario: Wraps folds and disjoint anchors
- **WHEN** selection originates from a wrapped source line, a folded display stop intersecting an anchor, or a row between disjoint anchor ranges
- **THEN** source display geometry determines candidate coverage, folded summary groups retain their combined expansion, and unanchored gaps do not count as coverage

#### Scenario: No covering explanation
- **WHEN** a row has neither a directly selectable summary nor any covering anchor
- **THEN** Enter/K leaves the pane collapsed without a chooser or an additional inference request

### Requirement: Explicit collapse at current position

Enter/K and Esc/q in detail SHALL collapse at the current source-aligned position, not a saved summary or invocation row. Mapped context SHALL retain its position. After cursor movement, prose SHALL use visual-row geometry bounded to visible anchors, with nearest-target and earlier-row tie rules. With untouched initialization or no visible anchor, collapse SHALL retain the native source position. Focus and source views SHALL be preserved within native geometry limits.

#### Scenario: Collapse without moving after initialization
- **WHEN** detail opens from source line 31 beneath a summary at line 20, or n/p initializes a new detail entry, and the user explicitly collapses without moving or scrolling
- **THEN** the current source position is retained rather than remapped from the newly placed detail header
- **AND** initialization events do not cause a source cursor or viewport jump

#### Scenario: Collapse after moving through continuation
- **WHEN** a note covering lines 20–40 is opened at line 25, the expanded cursor moves to source-aligned continuation at line 31, and Enter/K or Esc/q is pressed
- **THEN** overview and source cursors remain at line 31, not line 20 or line 25

#### Scenario: Collapse from prose
- **WHEN** the current prose cursor is visually aligned with anchored source line 31 although its Markdown buffer line number differs
- **THEN** explicit collapse selects overview/source line 31 rather than the Markdown row number, stale source cursor, summary, or invocation row

#### Scenario: Prose outside visible anchored positions
- **WHEN** the prose cursor is beside unrelated code, an unanchored gap, or empty EOF space and visible anchored targets remain
- **THEN** collapse selects the nearest visible anchored position, choosing the earlier position for equal distances, without snapping to an off-screen summary

#### Scenario: Anchors have scrolled off-screen
- **WHEN** all anchors have left the source viewport while the user reads long prose
- **THEN** explicit collapse preserves the current native source position and viewport instead of returning to an off-screen anchor

#### Scenario: Collapse on folded or deleted content
- **WHEN** the current source-aligned position is a closed fold or an old-side deleted line represented as new-side filler
- **THEN** collapse retains the corresponding fold start or real old-side line and synchronized native diff position without unfolding code or treating filler as a new-side line

#### Scenario: Collapse preserves current view and focus
- **WHEN** explicit collapse follows cursor movement or paired scrolling
- **THEN** source viewports are not restored to their expansion-time values, the explanation pane retains focus, and repeated synchronization events do not replay a jump
- **AND** removing prose can change the explanation layout, but does not force the overview cursor onto a summary

#### Scenario: Expanded controls do not reselect overlaps
- **WHEN** Enter/K is pressed in detail at a position covered by multiple explanations
- **THEN** it collapses at the current source-aligned position without opening an ambiguity chooser or expanding another explanation

### Requirement: Automatic-mode header indicator

Diff explanation panes SHALL show `Auto` in their existing winbar when automatic explanations are enabled, in both overview and expanded detail, independent of request state. Disabled mode and code panes SHALL omit it. The indicator SHALL use the existing muted header styling and appear alongside counts before lower-priority descriptions and hints; width clipping SHALL preserve counts and `Auto` whenever both fit.

#### Scenario: Enabled overview and detail
- **WHEN** automatic explanations are enabled and a diff pane is opened or expanded
- **THEN** its header displays `Auto` alongside its count and existing request or detail state
- **AND** the indicator remains present for pending, ready, unexplained, failed, stale, and cancelled states, not only during automatic requests

#### Scenario: Disabled or code pane
- **WHEN** automatic explanations are disabled, or the pane explains ordinary code regardless of the global setting
- **THEN** its header has no `Auto` indicator

#### Scenario: Narrow header
- **WHEN** an enabled diff pane is too narrow for its full header but wide enough for its count and `Auto`
- **THEN** both count and `Auto` remain visible while lower-priority descriptions, legend text, or navigation hints are abbreviated or omitted
- **AND** no header text is inserted into explanation content rows

### Requirement: Nondisruptive live mode indication

Toggling automation SHALL immediately update all open diff-pane headers, including background tabs and expanded detail. Header updates SHALL preserve request state, accepted notes, active jobs, selected explanation, detail buffer, cursors, viewports, and focus. The editor's local/global statusline and the existing request-state meaning of `vim.b.explainr_status` SHALL remain unchanged.

#### Scenario: Toggle while reading expanded detail
- **WHEN** the user toggles automation with a diff explanation expanded and its prose scrolled
- **THEN** `Auto` appears or disappears immediately without collapsing detail, replacing its buffer, moving the cursor or viewport, changing the selected note, or starting inference

#### Scenario: Multiple open tabs
- **WHEN** the user toggles automation while multiple tabs contain open diff explanation panes
- **THEN** every owned diff-pane header reflects the new setting without switching tabs or windows
- **AND** any code-pane header remains without an automatic-mode indicator

#### Scenario: Existing status integrations
- **WHEN** automation is toggled with a user statusline or lualine active
- **THEN** the editor statusline remains unchanged and `vim.b.explainr_status` continues to expose the existing request-state string rather than an indicator-decorated replacement

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

### Requirement: Comparison narrative reading mode

Diff readers SHALL offer Review and File modes in the same right-hand pane. Review SHALL display the whole-change narrative as read-only, independently scrollable Markdown, without source alignment, source focus decorations, or a floating window. File SHALL retain aligned overview and expanded detail behavior. Review SHALL use the explainr filetype, optional syntax highlighting, visible Markdown markers, and native wrapping without a renderer dependency.

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

### Requirement: Display-only narrative access

Explainr SHALL expose `:ExplainrReview`, `require("explainr").review()`, and a pane-local remappable `<Plug>(ExplainrReview)` action to select Review without inference. They SHALL show a retained narrative or an explicit pending, empty, failed, or stale state for the current comparison. No global default mapping SHALL be installed. Reopening the same narrative SHALL preserve its reading position.

#### Scenario: Return to the narrative
- **WHEN** the user scrolls Review, reads two files, and invokes ExplainrReview
- **THEN** the same narrative returns at its saved reading position without another request or selecting another Diffview file

#### Scenario: Narrative has not been generated
- **WHEN** ExplainrReview is invoked in a supported comparison without a retained or pending review
- **THEN** the reader shows an empty Review state directing the user to ExplainrDiff review
- **AND** opening that state does not generate explanations, including with Auto enabled

#### Scenario: No supported comparison
- **WHEN** display-only Review access is invoked outside a supported Diffview comparison
- **THEN** it reports the missing comparison without inference or changing a code explanation reader

#### Scenario: Review generation begins
- **WHEN** ExplainrDiff review is explicitly requested
- **THEN** the pane selects Review pending mode without stealing focus and preserves any still-fresh prior narrative while waiting
- **AND** a replacement narrative starts at its beginning only if Review is still selected when installed

### Requirement: Narrative file navigation and return

Enter on a rendered Review file reference SHALL select that exact comparison entry and show File mode after its panes become coherent, without inference for valid returned notes. Arbitrary narrative text SHALL not become an executable link. Esc in Review SHALL return to the current File overview; q SHALL close the reader. Actual Diffview file changes SHALL select File mode, while retaining the narrative reading position.

#### Scenario: Follow a renamed or deleted file
- **WHEN** Enter activates a validated reference to a renamed or deleted manifest entry
- **THEN** Diffview selects that entry using its comparison identity and File displays the correct available old/new notes rather than opening a guessed working-tree path

#### Scenario: Reference has no textual annotations
- **WHEN** a Review reference selects a binary or both-empty entry
- **THEN** the reader shows its no-text-annotations state without fabricating ranges or invoking a file explanation

#### Scenario: Enter on ordinary prose
- **WHEN** Enter is pressed on narrative text that is not a rendered file reference
- **THEN** no file navigation, command execution, note expansion, or AI request occurs

#### Scenario: Return and close have distinct controls
- **WHEN** Esc is pressed in Review
- **THEN** the pane returns to File overview without cancelling pending work
- **AND** q or ExplainrClose instead closes the reader and cancels owned pending work

#### Scenario: Navigate through Diffview bindings
- **WHEN** a configured next/previous-file action or explorer selection actually changes the file while Review is displayed
- **THEN** the pane shows that file's notes or pending/empty state, without cancelling existing generation
- **AND** a disabled mapping or a no-op navigation at a list boundary does not reset Review

### Requirement: Nondisruptive background completion

Background completion SHALL update retained results and request status without stealing focus, changing the selected file or reader mode, or resetting unrelated expanded detail or narrative reading position. A fresh replacement for a currently expanded file batch SHALL become visible after detail exits. Stale content SHALL be cleared or identified rather than preserved as current solely to avoid disruption.

#### Scenario: Hidden file completes
- **WHEN** A completes while the user reads expanded notes for B
- **THEN** B's detail buffer, selection, cursor, viewport, and source positions remain unchanged
- **AND** only A's retained result and background request status change

#### Scenario: Review finishes after the user leaves Review
- **WHEN** a review completes after the user navigates into File mode
- **THEN** the narrative becomes available without switching the pane back to Review
- **AND** an existing expanded file note remains open until the user exits it, unless its content became stale

#### Scenario: Off-screen failure
- **WHEN** generation for hidden A fails while B has valid notes
- **THEN** the error identifies A and does not mark B's accepted notes as a failed result

### Requirement: Review and background status

The diff-pane header SHALL identify the active Review/File mode and distinguish selected-target pending work from requests running elsewhere and queued work. Review SHALL show comparison/request state instead of file-note ordinals and retain Auto when enabled. No progress percentage or per-file completion progress SHALL be invented before a whole-review response validates. Status updates SHALL not alter the editor statusline or reset reading state.

#### Scenario: Other file is still generating
- **WHEN** B is selected while A runs and B is queued
- **THEN** the header distinguishes B's queued state from background generation rather than displaying A's notes or indicating that B is already generating

#### Scenario: Whole-review request pending
- **WHEN** one review invocation is running
- **THEN** Review reports pending comparison work and its target file count without claiming individual files have completed

#### Scenario: Narrow Review header
- **WHEN** the Review pane cannot fit its full header
- **THEN** it prioritizes active mode and request state, plus Auto when those fit, over hints and descriptions
- **AND** File retains its existing count/Auto priorities and neither mode inserts a header into buffer content

## Decisions

- Keep the right-side, sparse annotation pane (Option A), not ghost-text-only annotations or a standalone prose reader. Source wraps, folds, comparison membership and text remain authoritative.
- Replace the original floating-detail plan with in-pane expansion so detail never covers the code it explains. Preserve neighboring notes and use explicit expansion rather than automatic expansion on ordinary cursor movement.
- Give overlapping notes separate lines, not a horizontally concatenated fallback. Reserve primary positions first; overflow labels and cursor targets preserve meaning when perfect one-to-one screen alignment is impossible.
- Use theme-derived neutral focus surfaces and gutter rails rather than fixed gray/green blocks or code underlines. Preserve Git backgrounds and signs; do not force source signcolumn settings.
- Replace the traveling loading wave with steady backgrounds and animated gutter rails. Avoid cursor-cell repainting, but do not promise to eliminate terminal flicker when synchronized output is disabled.
- Use optional Markdown syntax highlighting with visible markers and native wrapping, without renderer integration or changes to user renderer setup. These decisions supersede the UI assumptions in the archived initial design.
