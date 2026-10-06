# Design

## Context

See `proposal.md` for motivation and `specs/aligned-explanation-ui/spec.md` for the behavior contract. Design is warranted because event ordering must distinguish user reading from source-driven placement and initialization while retaining native scrolloff/diff behavior.

`lua/explainr/ui.lua` owns the entire flow. Expanded Ctrl-e/Ctrl-y mappings call `pane:scroll()` directly. That method forwards the actual display-row delta, with a special backward-scroll fallback at the reader's upper limit. Before forwarding, a source cursor inside its scrolloff margin can be temporarily centered with `normal! M`; this prevents margin correction from consuming the requested scroll distance. `sync_sources(..., scrolling=true)` deliberately leaves native bound cursor positions alone. Finally, `scroll()` saves all `scroll_views` without selecting the reader's target.

The prose branch of `pane:sync()` selects only when the reader's line or column differs from its cached view. The mapped scrolling path has already refreshed that cache, and sticky-edge scrolling can change the source target without moving the reader cursor at all. The active-context branch also resolves its target before calling the scrolling path, so target resolution needs a consistent post-scroll order.

Executed exploration on Neovim 0.12.5 used a 200-line source, anchors 40–100, a short top-pinned card, and a reader cursor on its fourth content row. With scrolloff 0, Ctrl-y left the source cursor at 73 although the final target was 72. With scrolloff 5 and 999, the corresponding actual/target pairs were 78/67 and 69/59. Invoking the existing `detail_target()` and `select_source()` after scrolling repaired all three cases, preserving source toplines, options, and settled positions through repeated cursor/scroll/idle/redraw events. This verifies the corrective primitive in code mode, not the complete diff or renderer integration. The current UI suite passes all 131 tests; the affected scrolling tests assert deltas and stability without checking the final reader/source cursor relationship.

## Goals / Non-Goals

**Goals:**
- Complete each explanation-driven reading action in the existing UI owner: native reading action, paired viewport synchronization, any necessary placement, final target selection, then final view snapshots.
- Share target semantics between direct mapped scrolling and observed native cursor/viewport changes without adding another navigation controller or relying on a later event to repair selection.
- Keep cursor selection separate from scroll-distance calculation so correct viewport movement is not replaced by snapping code toward prose.

**Non-Goals:**
- Rework sticky layout, comparison coordinates, context caching, native scroll bindings, or the existing margin-normalization algorithm.
- Select off-screen anchors, infer semantic paragraph-to-code relationships, or force source columns onto a particular wrapped segment.
- Modify collapsed navigation, add mappings/options/dependencies, or change source text, renderer configuration, session behavior, or runtime auto-explanation controls.

## Decisions

### 1. Complete selection in the shared expanded reading flow

Make the existing `scroll()` / `sync()` ownership path complete final selection under its synchronization guard, rather than wrapping just the two key mappings. Determine whether a genuine reading action occurred from the pre-action views and the actual result: reader cursor motion, reader viewport motion, or successful source movement through the sticky backward-scroll fallback. An explicit key with no effective motion is not a reason to remap initialization or a source-owned cursor. Native observation and direct key execution must reach the same completion behavior.

Finish scroll forwarding and existing diff synchronization first. Finish any sticky placement/reflow that is part of that reading action next, then resolve the current reader target. An unchanged Markdown line/column must not suppress selection if the source viewport moved. Resolve active-context targets after pending scrolling instead of retaining a target calculated before placement. Avoid duplicate selection in the existing prose/context `sync()` branches when the shared path has already completed it; choose the smallest local control-flow change, not new persistent controller state.

Keep source-driver calls, opening/n/p initialization, layout-only reflow, and repeated unchanged events outside reading selection. The existing `detail_reflow()` distinction must still rebaseline renderer corrections without forwarding them as scrolls. A source event caused by a completed reading action must see final snapshots and must not restart the action.

**Alternatives rejected:** calling `sync()` after the key mapping still loses the pre-action cursor evidence; comparing only Markdown line/column misses sticky Ctrl-y; unconditional selection in every scroll/event callback would override source navigation and initialization.

### 2. Reuse exact-context and visible-anchor target selection

Reuse `detail_target()` for the final target and `select_source()` to apply it. Active context retains its exact comparison coordinate. Prose uses its actual content-screen row, including the current wrapped segment, bounded to visible anchored display stops. Continue selecting real old-side deleted code when the followed side contains filler, retaining fold starts, nearest-visible targets, and earlier-row ties. If prose has no visible eligible target, keep the native post-scroll source cursor unchanged.

The existing outside-context destination/collapse behavior remains authoritative. Programmatic sticky relocation and source-only scrolling must not be interpreted as intentional outside-context motion; real reader motion into outside context still collapses at that destination. Do not derive targets from Markdown buffer line numbers or use the temporary normalization cursor as a semantic destination.

**Alternatives rejected:** mapping paragraph numbers to code fails on wraps/folds/filler; clamping to an off-screen absolute anchor would undo free reading; restoring the pre-scroll cursor ignores the changed target at a sticky edge.

### 3. Preserve views and snapshot only the settled state

Retain the current scrolloff normalization because it solves viewport-distance correction; its cursor is temporary whenever a reader target exists. Apply final source selection through the existing view-preserving routine after native scrolling and diff binding have settled. Preserve local scrolloff inheritance (`-1`) and global/local values, explanation focus, diff membership/bindings, and source columns within the existing target-line clamp.

Keep all corrections under the current synchronization guard, then refresh source and reader `scroll_views` only after final placement, selection, and any required rendering. Post-scroll selection must not introduce another viewport delta. Repeated CursorMoved, WinScrolled, SafeState, and redraw processing must retain both the final cursor and viewport, not merely stabilize a wrong cursor.

**Alternatives rejected:** removing normalization risks consuming part of the requested delta; permanently setting source scrolloff to zero changes user navigation; deferring selection until another event makes correctness depend on callback ordering.

### 4. Verify the missing relationship rather than only stability

Extend focused UI tests using real feedkeys plus settled editor events. Derive expected target lines independently from asymmetric fixtures and known display positions, never from the production `detail_target()` method. The simplest decisive case is source topline 70, top-pinned fourth-row prose cursor, scrolloff 0, and Ctrl-y: the expected final cursor is 72 with topline 69, not the previous line 73.

Cover effective margins 0, 5, and viewport-centering values, including inherited local `-1`; both sticky edges and release; counted scrolling that forces native reader cursor motion into active continuation; actual wrapped/folded display rows; old-only deletion filler with unequal diff margins; and no-visible-anchor/native-limit fallbacks. Assert final target, viewport delta, preserved options/focus, and idempotence together. Preserve source-driver, initialization, entry-navigation, reflow, and collapse checks. Add only cases that distinguish plausible wrong implementations, extending existing fixtures where possible.

Capture representative affected states through the existing Neovim screen-grid workflow and inspect cursor/source row alignment after sticky scrolling, not only the static card. Use native and optional renderer paths when the renderer is installed; its absence must not block native correctness.

## Risks / Trade-offs

- [Selection runs before sticky placement or uses stale context] → Resolve against the final layout and assert pin/release plus counted-context destinations.
- [Final selection triggers another scrolloff/diff correction] → Reuse view-preserving selection and assert unchanged post-scroll viewport origins after real redraw and repeated events, including unequal diff margins.
- [Source events are mistaken for reading actions] → Capture pre-action evidence before snapshots and retain source-driver/initialization/reflow exclusions.
- [Added target projection expands scrolling work] → Reuse comparison caches and viewport-bounded projection; retain the existing large-file scrolling checks rather than scanning the full source.
- [Existing viewport-only tests pass while cursors are still wrong] → Assert independent expected cursor lines, using asymmetric inputs at actual margin and sticky boundaries.

## Migration Plan

No configuration, data, or API migration is required. Implement locally in `ui.lua`, extend the UI tests, and update the existing expanded-navigation documentation. Run the targeted UI suite and full editor suite, then capture and inspect affected states. Rollback reverts this change's synchronization, tests, and documentation only; no changes to sticky layout or the unrelated runtime-toggle work are required.
