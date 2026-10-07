# Design

## Context

See `proposal.md` for motivation and the delta spec for acceptance behavior. The screenshots and reported flash are user observations; the transient frame has not yet been reproduced under an attached UI.

`lua/explainr/ui.lua` owns both input and presentation. Expanded Ctrl-e/Ctrl-y mappings call `pane:scroll()`, which executes native movement before measuring its display-row delta. `pane:place_detail()` separately clamps fitting cards by adjusting leading context and restoring the reader view. `WinScrolled`, `CursorMoved`, and `SafeState` reconcile geometry, with `SafeState` able to schedule a full placement refresh when the source projection changes. This ordering is a plausible source of scroll-then-correction frames, not a proven diagnosis.

There is already a Ctrl-y fallback when the detail buffer has no earlier rows, and an outside-context collapse path in `pane:sync()` using `detail_target()` and `back(true)`. Existing tests cover native limits, sticky source scrolling, display-row deltas, and collapse destinations, but settled-state checks alone cannot rule out intermediate visible frames.

The main spec distinguishes source-owned sticky placement from reader-owned scrolling. This change preserves that distinction, narrows the native-limit no-op rule to genuine native limits, and adds a deliberate reader-only context escape. It does not reinterpret every pinned card as an exit request.

## Goals / Non-Goals

**Goals:**
- Make a mapped scroll's placement, source selection, and cached views settle together before later events can reinterpret them.
- Use current display geometry and existing source-backed context ownership for boundary decisions and destinations.
- Reuse the existing collapse lifecycle instead of adding another navigation mode or destination mapping.

**Non-Goals:**
- A generic scroll controller, new window, animation system, terminal configuration change, or global redraw suppression.
- Symmetric auto-collapse for Ctrl-e at the top, new page/mouse escape semantics, or changes to source/overview mappings.
- Replacing native long-prose scrolling, changing anchor membership, or changing the top-edge k shortcut.

## Decisions

### Settle explicit input before deferred reconciliation

Keep ownership in `pane:scroll()` and `pane:place_detail()`. For explicit reader Ctrl-e/Ctrl-y, resolve the applicable native, fitting-card, or escape case using the current viewport and rendered card height. Complete the valid source movement, fitting-card placement where required, final cursor selection, projection refresh, and `scroll_views` snapshots within the existing synchronization guard. Later source events must observe this as completed reader input, not initiate another placement correction.

First capture the actual event/frame sequence for the reported top-edge case. If a native scroll exposes an intermediate frame even inside the guarded action, bypass that transient reader motion for the fitting pinned-card case and derive the final view from the actual native source delta. Do not suppress valid long-card reading offsets or clamp all reader actions indiscriminately. No global `lazyredraw`, `termsync`, timers, or forced terminal settings are part of the fix.

**Alternative rejected:** repairing the reader in another scheduled callback retains the visible bounce and can replay source movement. Disabling sticky placement entirely changes unrelated source-driven behavior.

### Classify the bottom escape before consuming the blocked step

The escape applies to explicit reader Ctrl-y from the card when all of these hold: the card fits, its final rendered bottom is already at the content viewport edge, the next step is blocked by card placement rather than a native source limit, and a preceding source-backed display row exists. Counted commands must distinguish reaching the edge from attempting another step beyond it. Determine the boundary from display rows, excluding the winbar/statusline, not from Markdown line count or a stale opening position.

Move to the context immediately above the card, not to an arbitrary previous note or an unconditional `source_line - 1`. Resolve folds, wrapped segments, old-side deletions, and disjoint anchors using the current context/projection mapping. An outside-anchor destination uses the existing automatic-collapse path, preserving focus and current source view. An inside-anchor destination remains expanded. Once the cursor is in context, ordinary context navigation takes over; do not repeatedly force it back to the same escape row.

Do not run the blocked source scroll and then undo it. The escape itself is cursor movement; any viewport adjustment is limited to native visibility of the destination. If no real preceding row exists, retain native scrolling/limit behavior rather than manufacture a destination.

**Alternative rejected:** unconditional collapse whenever the bottom touches the viewport disrupts reading and source-driven pinning. Always moving to the previous source line ignores diff ownership and wrapped/folded display geometry.

### Stop a counted command at the escape destination

Planning default: process the valid scrolling portion of a count, use the first blocked step for the escape, and stop that command there. Do not replay the original count or apply leftover steps to the collapsed overview. This keeps a mode-changing action at a predictable destination and bounds it to one escape. A count ending exactly at the edge does not escape. Preserve efficient native counted scrolling away from this boundary rather than iterating arbitrary large counts row by row.

**Alternative rejected:** forwarding the remaining count after collapse can move the user away from the requested adjacent context before it is visible. Counts in ordinary scrolling and the top-edge k shortcut retain their existing meaning.

### Verify intermediate frames as well as final state

Extend existing `tests/ui_test.lua` fixtures rather than adding a separate testing framework. Use real key input and queued event delivery, with explicit expected destinations, source deltas, and final detail state. Include one-step-before, exactly-at, and one-step-beyond placement boundaries; these distinguish the intended escape from early collapse and permanent blocking.

Use the actual UI-grid machinery in `tests/render.py` / `tests/visual.lua` for top-edge repeated Ctrl-e and bottom-edge Ctrl-y. Retain each flushed frame around input and reconciliation, not just a final screenshot. Assert that no displayed frame moves the fitting card off the top and then restores it as a correction; inspect representative captures of the pinned card and the collapsed destination. A final image is evidence of layout only, not proof of no flicker. Keep generated artifacts under locally excluded `.amp/in/artifacts/`.

## Risks / Trade-offs

- [Root cause is inferred from event ordering] → Reproduce with attached UI frame/event capture before changing reconciliation; record whether native motion or a later callback presents the transient state.
- [Preflight misclassifies prose scrolling as a placement block] → Test fitting, exactly viewport-filling, and taller wrapped cards, plus an interior prose cursor and source-driven movement.
- [Stale context sends collapse to the wrong source] → Resolve against current projection; test an anchored predecessor and an outside predecessor, folded rows, and old-only deletion ownership.
- [Deferred callbacks undo the escape] → Cache only final views, invalidate expanded work through existing lifecycle/generation guards, and replay scroll/cursor/idle events in regressions.
- [Count handling changes at the mode transition] → Document the stop-at-escape default and test counts that stop before, at, and beyond the edge.
- [Scrolloff normalizations introduce extra movement] → Retain existing view-preserving selection; cover inherited/local margins and unequal diff margins without permanently changing options.

## Migration Plan

No data, configuration, or public API migration is required. Implement within the existing UI owner, update the scrolling documentation, run targeted and full offline suites, and inspect actual UI captures. Sync the delta into the main spec through the normal completion workflow. Rollback consists of reverting the localized behavior, tests, and documentation; no external state changes are involved.
