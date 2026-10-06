# Design

## Context

See `proposal.md` for motivation and `specs/aligned-explanation-ui/spec.md` for the contract. Design is needed because direct row selection, original anchors, asynchronous selection, and expanded display geometry have different ownership.

`lua/explainr/ui.lua` owns this behavior. `pane:note_ids()` collects summaries from `self.rows` and closed folds; `pane:detail()` currently does nothing when that selection is empty. Rendering gives overlaps separate positions in `locations`, preserves original anchors, and records overflow cursor targets. `pane:ranges()`, `coordinates()`, `locate()`, and `M.project()` already describe source/comparison/display geometry.

Explicit detail mappings call `pane:back()`, which restores `self.overview.view` and can synchronize sources back to that saved cursor. In contrast, `pane:sync()` already handles mapped continuation/context destinations and automatic collapse outside anchors. Prose currently lacks continuous source cursor mapping; the separate `sync-expanded-prose-cursor` proposal defines anchor-bounded visual-row selection. `tests/ui_test.lua` explicitly expects a move to continuation line 14 to collapse back to summary line 4, so those expectations must change deliberately rather than remain as accidental compatibility.

## Goals / Non-Goals

**Goals:**
- Keep summary identity, range coverage, and collapse destination separate, while sharing authoritative source geometry.
- Preserve existing in-pane detail layout and summary placement; range-based opening is not entry navigation.
- Make explicit collapse destination-driven without replaying saved cursor or viewport state.

**Non-Goals:**
- Change summary allocation, source text, editor bindings, collapsed hover/focus semantics, or AI prompts/results.
- Automatically expand on cursor motion, silently pick the shortest range, or add a custom picker framework.
- Implement continuous prose synchronization or the separate persistent-header change.
- Guarantee the exact terminal cursor cell survives removal of wrapped prose; preserve the corresponding source position and view instead.

## Decisions

### 1. Keep direct row selection and add coverage only to expansion

Retain `note_ids()` as the source of direct summary/fold selection and collapsed focus. In the no-index expansion path, use those IDs first, including summaries relocated outside their anchors. Only an empty direct selection falls back to original anchor coverage. Do not broaden `note_ids()` itself: that would also change focus, counts, and fold grouping while merely moving across blank rows.

Resolve the cursor's represented comparison position using existing projection, filler/overflow metadata, and folded extents. Intersect that position with each note's separate `ranges()` intervals; deduplicate note IDs across old/new or multiple anchors. Do not collapse disjoint anchors to an enclosing interval or treat a summary's allocated position as the explained range. Fold stops intersecting anchors are eligible; folds with directly selected summaries keep their existing combined card.

Partition covering IDs by `kind == "overview"`. One candidate opens directly; exactly one local candidate wins over covering overviews. Multiple local candidates invoke a chooser containing all covering IDs. As a minor deterministic fallback, multiple overview-only candidates also use the chooser rather than arbitrarily selecting one. Within each partition preserve existing displayed entry order; do not introduce another specificity or intent ranking.

**Alternatives rejected:** range selection in the shared focus helper changes unrelated interaction; smallest-range selection hides competing meanings; always prompting for overview overlaps makes ordinary full-file reading unnecessarily modal.

### 2. Use the existing detail path without its navigation side effects

Keep the distinction between an explicit n/p destination and a selected note for initial expansion. The latter must not take the navigation branch that centers a source on the selected summary. Feed the selected ID(s) into the existing card construction while retaining the source cursor/views at the invocation position.

Keep expansion attached to `locations[selected]`, retaining preceding/following notes and the existing off-screen or bottom-of-window fallback. Capture source views and keep existing synchronization guards so the initial detail cursor event cannot move code. Source-driven movement and explicit entry navigation continue to use their existing paths.

### 3. Let Neovim own the ambiguity UI

Call `vim.ui.select` with note-ID-bearing items, a concise prompt, and `format_item` labels using original side/range references and summaries. Local items appear before overviews; preserve stable display order within each group and label overview items clearly. The chooser selects identity only: the explanation itself still renders in-pane, with no AI request and no dependency on a particular picker implementation.

On cancellation, leave the pane collapsed and do not restore views over any user movement. Before accepting a delayed callback, check that the pane/result and its selection request still belong to the same collapsed view and comparison. Discard obsolete selections after close, result/file replacement, a newer selection request, or another expansion. Do not take focus from an unrelated window if the user has left the pane during an asynchronous chooser. These checks are needed because `vim.ui.select` can be overridden with asynchronous UI.

### 4. Resolve an explicit collapse destination before swapping buffers

Separate user-triggered collapse from result replacement, teardown, and automatic outside-anchor collapse. The explicit action computes its destination while detail metadata still exists; cleanup retains its existing noninteractive behavior. Do not globally replace every `back(true)` path with current-cursor navigation.

- For source-backed continuation/context, resolve the exact `detail_layout.rows` item through the existing comparison/fold machinery.
- For prose after user movement, resolve the actual cursor display row and column against the current source viewport, excluding header offsets. Restrict eligible targets to the expanded IDs' original anchors, including combined cards; choose the nearest visible target with earlier-row tie-breaking. Preserve disjoint gaps, wraps, folds, real old-side deletion ownership, and EOF distinctions.
- If no eligible anchored target is visible, retain the current native source cursor rather than selecting an off-screen summary or anchor.
- An untouched initialization cursor is not a user movement. Immediately collapsing after range-based expansion or n/p initialization retains the current source position, rather than mapping the newly placed detail header to another code line. Track initialization using the existing cursor/view lifecycle, not the original invocation row as a future restore target.

Restore overview options/folds, but rebuild the overview destination and alignment from the resolved source position and current source views instead of restoring saved `lnum`, `topline`, or expansion-time viewports. Preserve valid source columns and current paired views; use the existing native counterpart synchronization when a diff side owns the destination. Keep explanation-window focus. Refresh synchronization caches only after the final state so queued editor events cannot replay the old summary jump.

Collapsed focus comes from the destination row: blank rows clear it; a visible summary receives normal summary focus. Do not retain the previously expanded IDs solely to keep a highlight or ordinal. Enter/K in detail continues to collapse, never opening the overlap chooser.

**Alternatives rejected:** copying the Markdown cursor row fails for prose/wraps; restoring the invocation position loses subsequent movement; using a potentially stale source cursor for all prose ignores the user's current display position; restoring old viewports before applying a destination produces avoidable jumps.

### 5. Share collapse geometry with the companion change, not its scope

Use the same anchor-bounded visual-row semantics as `sync-expanded-prose-cursor`. If its source-target resolver is already implemented, reuse it at explicit collapse. If not, implement the resolver needed at collapse time here without adding continuous prose cursor movement; the companion change can then reuse that coherent responsibility. Do not create two competing algorithms or assume the companion implementation has landed.

This delta leaves `Free expanded cursor and scrolling` untouched so either archive order preserves the companion change's amendments. It deliberately replaces the main spec's saved-entry collapse and summary-focus scenarios. The header change must not alter target selection: use content-relative rows rather than hard-coded terminal offsets. Re-run combined UI checks when those changes meet in `ui.lua`.

## Risks / Trade-offs

- [Range selection accidentally changes focus or entry order] → Keep direct-selection/focus contracts intact and test summary precedence with overlapping overview/local notes and overflow rows.
- [Projection mistakes select unrelated diff or gap lines] → Use original intervals and comparison coordinates; test asymmetric old/new ranges, old-only deletions, folds beginning before anchors, inclusive boundaries, and disjoint gaps.
- [Late picker callbacks open the wrong file or steal focus] → Capture selection ownership and test delayed completion after replacement, close, newer selection, and focus departure.
- [Collapse restores a stale summary or triggers scrolloff movement] → Assert exact destinations, source columns/views, retained pane focus, and idempotence across repeated editor events; only native representability limits justify layout changes.
- [Opening at a continuation and immediately closing maps the initialization header instead] → Cover no-motion collapse separately from user movement and do not use initialization events as navigation.
- [Parallel changes edit the same owner] → Share visual-target resolution, preserve header ownership, and verify both isolated and combined behavior without modifying their planning artifacts.

## Migration Plan

No configuration or result-data migration is needed. Update all three UI-facing documents to replace summary-only expansion and saved-summary collapse language, including focus after collapse. Tests asserting old jumps must be updated to current-position expectations, while automatic outside-range collapse, n/p counts/centering, and result replacement retain their contracts. Rollback restores the prior selection/collapse paths and their documentation; no persisted state requires conversion.
