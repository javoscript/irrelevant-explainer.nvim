# Design

## Context

See `proposal.md` for motivation and the `aligned-explanation-ui` delta for the behavior contract. Design is needed because source-driven placement and explanation-driven reading currently share one viewport-delta path and must become distinct without feedback loops.

`lua/explainr/ui.lua` owns the reader. `pane:detail()` uses the existing right-hand split, builds Markdown plus real blank context/continuation rows, and records their source coordinates in `detail_layout`. `pane:scroll()` currently forwards source scrolls to detail and detail scrolls to sources. An executed headless check opened a seven-row card at source line 40, then scrolled code 25 display rows: detail stayed selected but every card row became invisible. `tests/ui_test.lua` also explicitly expects equal source/detail movement for both drivers.

The persistent matched winbar is now implemented. Prose cursor mapping uses current content-relative display positions bounded to visible anchors. The in-flight `expand-from-anchor-range` change implements current-position collapse and summary-free range selection. These behaviors are integration constraints, not work to repeat here. The existing expanded `schedule()` path skips geometry rebuilds, so sticky resize/fold updates need an explicit expanded-layout path.

## Goals / Non-Goals

**Goals:**
- Separate source-owned placement from explanation-owned reading in the current UI owner.
- Keep native scrolling, real cursor-addressable prose/context, and existing comparison geometry authoritative.
- Preserve reading state and cursor/collapse semantics when surrounding presentation rows move.

**Non-Goals:**
- Add another window, a floating overlay, a standalone fixed reader, a generic layout controller, or a new dependency.
- Pin only the summary, infer semantic paragraph-to-code relationships, change anchor eligibility, or auto-select notes while scrolling.
- Force source motion past native EOF limits or require neighboring context to fit beside a viewport-filling explanation.

## Decisions

### 1. Keep the current detail buffer and reposition its presentation context

Implement sticky layout in `ui.lua` using the same split and Markdown buffer. Keep prose content stable while updating the leading/trailing display-only context and viewport. Preserve the buffer-relative prose cursor and logical reading position before changing presentation rows; restore them relative to the relocated prose span, including the cursor column and a later wrapped segment. Refresh `detail_layout.rows`, `first`/`last`, active gutter flags, and context decorations together so their meaning never lags behind the display.

Separate the card's summary/metadata/prose height from blank anchored continuation. A short card for a large range is still a short card; its range rail must not turn sticky placement into a full-range-height calculation. Keep neighboring summaries as dimmed, navigable context where space allows, and preserve their accessibility when they cannot fit immediately on screen. Refresh optional Markdown rendering after placement without repeating filetype/buffer attachment.

**Alternatives rejected:** a float duplicates rendering/lifecycle and obscures context; forcing a separate split changes the interaction model; repeatedly calling `detail()` resets initialization/reading state and risks entry-navigation side effects.

### 2. Clamp natural placement in content display rows

Retain the selected summary's natural display position independently of the clamped card position. Use its existing allocated comparison location, including overflow/filler ownership, not the range start or prose line number. Update natural position from actual source display-row movement, and recompute against authoritative geometry after resize, source-side changes, folds, or diff updates. An off-screen summary still has a position relative to the viewport; zero from `screenpos()` alone cannot distinguish above from below.

Let available height exclude the winbar/statusline and let the measured card height include actual wrapping and renderer geometry. For a fitting card, clamp its natural first content row between row 1 and `available height - card height + 1`. This gives top and bottom pinning, leaves interior alignment untouched, and naturally releases a card when its original position fits again. Unclamped position must remain independent so reverse scrolling does not accumulate drift.

For detail taller than the viewport, use the content-height reading area with its existing logical prose offset. Code-driven placement preserves that offset; it must not restart the detail at its summary. On width changes, preserve the logical text position and choose its corresponding new wrapped segment rather than insisting on an obsolete numeric display-row offset. A separately sticky summary is not part of this change. If native geometry leaves fewer rows than the full card, show the largest available reading area without enlarging or scrolling a source window.

**Alternatives rejected:** always placing detail at the top loses aligned behavior; clamping raw buffer line numbers fails for wraps/folds/filler; including continuation in card height clips otherwise fitting detail.

### 3. Give each scroll driver a different responsibility

Extend the existing `pane:scroll()` branch rather than adding a parallel scroll controller:

- **Explanation driver:** execute or observe the native reading action, measure its actual viewport delta, and move paired sources by that display-row distance within native limits. Do not clamp away or replay that user reading movement. Cursor motion with no viewport delta retains existing anchor-bounded source selection.
- **Source driver:** let code and its diff counterpart finish their native motion, then update natural card placement and apply sticky bounds while retaining prose reading state. Do not forward the entire source delta as a reading scroll, map the inactive prose cursor onto code, or feed the placement correction back to sources.
- **Geometry-only update:** recompute bounds and context under guards without treating resize/reflow as a user reading scroll.

Use observed viewport distance rather than blindly replaying keys after a driver reaches EOF or a wrap/filler boundary. Both diff sides and mouse-wheel targeting must select the actual driver using existing ownership/event routing. After an explanation-driven source move, later bound-window events are consequences of that move, not fresh code-driven actions that should reset or reclamp the reading view.

Respect inherited and per-window source `scrolloff`, including unequal diff margins. Reading can select an anchored row inside a margin while preserving the viewport. Before forwarding another reading scroll, normalize only such a source cursor to the viewport's native middle, restoring its original local/global inheritance before executing the native scroll. Measure its position from saved native text geometry, not stale screen caches. Validate bound counterparts before `syncbind` computes distances: native `scrolldown` otherwise applies a pending cursor-margin correction after calculating its distance, causing drift. Viewport synchronization retains native bound cursor positions; explicit prose and active-context selection share the view-preserving source-selection path. Do not permanently override source options.

Apply presentation changes under existing syncing/rendering guards and refresh all `scroll_views` only after final cursor/view changes. Deferred CursorMoved/WinScrolled/SafeState callbacks must see the final snapshots and be idempotent. Layout-only changes must not set the user-reading flag: source pinning is not a prose motion and must not turn an untouched initialization into a collapse remap.

**Alternative rejected:** retaining symmetric delta forwarding and correcting it afterward generates extra scrolls, cursor coercion and feedback; independently scrolling prose would contradict the agreed code-follows-explanation behavior.

### 4. Preserve target semantics and use existing lifecycle ownership

Rebuild source-backed context mappings from current projection/comparison coordinates when moving context rows; do not reuse stale opening-screen coordinates. Continue using `detail_target()` for actual prose/context motion and explicit collapse. Pinning changes placement, not source ownership: original disjoint anchors, nearest-visible/earlier-row tie rules, folded starts, real old-side deletion targets, and no-visible-anchor fallback remain unchanged.

Retain natural automatic collapse when the user intentionally moves into outside context, but do not interpret a programmatic context relocation as that user motion. Explicit collapse must preserve the current source viewport and destination, never restore the source view saved when pinning began.

Reset placement/reading metadata on n/p/N entry initialization, and clear it through existing back/set/close/file-switch paths. Route expanded resize and relevant fold/diff geometry updates to layout recomputation rather than the overview-only scheduling path. Preserve source options, user headers/statusline, selection identity, ranges, tint, gutter and buffer reuse.

**Alternative rejected:** treating a pinned card's screen position as a new anchor would select unrelated code and break the current prose/collapse contract.

## Risks / Trade-offs

- [Directional scrolling replaces an existing equal-delta guarantee] → Modify only `Free expanded cursor and scrolling`; preserve its other scenarios and split driver-specific tests explicitly.
- [Native cursor visibility or scrolloff moves prose during a placement change] → Save/restore logical reading state under guards and assert the post-layout source views and paragraph/column, including wrapped segments.
- [Long-card reading scroll is accidentally undone by a source event] → Cache final paired views and test actual queued events, not only direct method calls.
- [Context reallocation leaves stale coordinates or rendering marks] → Update layout and decorations atomically; test outside-context collapse and renderer refresh after both pin edges.
- [A visible card outlives its off-screen code anchors] → Keep original range labels and anchor-bounded mapping; never pull code back just to satisfy cursor mapping.
- [Geometry measurement depends on optional Markdown rendering] → Use native display-height/projection APIs and verify with renderer available and unavailable; no renderer requirement.
- [Concurrent changes share `ui.lua` and tests] → Preserve existing work, integrate with current-position collapse, and rerun the combined UI/full suites before completion.

## Migration Plan

No configuration, data, or API migration is required. Update the three UI-facing documents to describe source-driven sticky placement and explanation-driven paired scrolling. Revise the source-driven half of existing symmetric-scroll tests rather than weakening their explanation-driven checks. Use `tests/visual.lua` and `tests/render.py` to capture and inspect actual aligned, top/bottom-pinned, long-detail reading, and resized states; generated concepts are not verification evidence. Rollback reverts only this change's layout/scroll handling, regression tests and documentation.
