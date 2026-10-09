# Design

## Context

See `proposal.md` for motivation and the capability deltas for the behavior contract.

`session.lua` owns the selected comparison/file identity, accepted batches, pending requests, and asynchronous saved-note restoration. Its `follow()` path detects a changed file key, calls `pane:back(true)`, clears the old binding, then waits for coherent Diffview sources before restoration or existing automatic inference. `render()` assembles accepted notes and calls `pane:set()` only when content changes.

`ui.lua` owns deterministic displayed order (`note_order`), indexed detail selection, off-screen detail placement, source geometry, and cleanup. Manual `detail(index)` currently focuses the explanation window on first expansion. Expanded entry navigation intentionally moves to an anchor, so automatic first-note expansion must use initial indexed expansion rather than simulate `n` or a jump.

`diffview.lua` copies resolved navigation/explorer mappings rather than hard-coding Tab. Its original actions and mapping options must remain authoritative. Source-side navigation must work without installing new global or source-buffer mappings.

The existing `Detail gutter lifecycle isolation` scenario unconditionally restores saved notes in overview. The delta replaces that assumption with the expanded/collapsed navigation rule, retaining the old-detail teardown and gutter isolation guarantees.

## Goals / Non-Goals

**Goals:**
- Keep navigation intent in the session that owns the comparison and target; keep expansion geometry in the existing UI.
- Cover saved-note restoration and generated/cached completion through the same accepted-result display boundary.
- Preserve focus, native source positions, freshness, queue ownership, and existing mapping semantics.

**Non-Goals:**
- A persistent reading-mode preference, initial auto-expansion, or a new option/command.
- Changes to generation eligibility, caching, review synthesis, or result schemas.
- Auto-expansion on ordinary cursor movement, Refresh, repeated Explain, or Review-to-File transitions.
- Restoring the previously selected note on another file; continuation always selects the first displayed note.

## Decisions

### 1. Capture real expanded state before navigation teardown

Use the session's file-follow lifecycle as the source of truth for actual selected-file changes, not a literal Tab mapping or focus at completion time. Capture whether File detail is expanded before `follow()` tears it down and binds the new target. Preserve this snapshot across deferred source-buffer readiness; do not derive it from the already-reset pane. If another automatic teardown can run first, pass the pre-teardown state into this same session transition rather than adding a second navigation state machine.

The expansion condition has no originating-window restriction. Observing the owned file transition also covers next/previous actions invoked in source windows and remapped actions without rewriting Diffview's mappings. A no-op action at a list boundary never changes the target and never tears down detail. Review supplies no File-detail intent.

Rejected alternatives: wrapping only Tab misses remaps and source navigation; checking focus on result arrival misclassifies delayed operations; storing a sticky expanded preference would expand after the user reaches an empty/collapsed file.

### 2. Keep one target-bound, one-shot expansion intent

Maintain at most one pending intent on the owning session, bound to its comparison/file key and current navigation lifetime. Reuse existing generation/ownership guards for asynchronous work. Bind the intent to the new target, not the discarded detail buffer or request identity: restoration, cache hits, existing pending work, and review-distributed notes can all supply that target's valid notes.

After accepted target notes are installed and the overview's order is built, consume the intent before opening `note_order[1]`. Check that the target is still selected, File is still active, no user-selected detail has replaced the choice, and the intent has not been retired. Status-only updates cannot create or replay intent. Empty completed results retire it. An unexplained target with no work shows the ordinary empty state; it does not keep a persistent expanded preference for subsequent navigation.

Subsequent navigation recomputes eligibility from the actual current detail state. Retire pending intent on user reading choices, user focus/tab changes after navigation, Review entry, Cancel/Refresh, failure, invalidation, ownership replacement, or closure. Distinguish user actions from programmatic buffer swaps and initialization events so normal restoration cannot cancel its own intent. Source-originated navigation remains eligible without requiring reader focus; later user focus changes cancel the deferred action.

Rejected alternatives: opening in every `pane:set()` or `show_file()` would affect Refresh, initial opening, background updates, and explicit collapse; linking intent to an inference request would miss saved-note restoration and conflate display with generation.

### 3. Extend the existing detail path to preserve focus

Allow the existing indexed detail-opening path to suppress its manual focus transfer for automatic expansion, preserving manual behavior by default. Use the first ID in rendered `note_order`, not raw `result.notes[1]`, cursor-overlap selection, or an ambiguity chooser. Reuse the normal detail buffer, header, gutter, context, and off-screen fallback.

Automatic initialization must not invoke expanded entry-navigation centering or map the new prose cursor back onto code. The target's source cursors and viewports after native navigation are the baseline to preserve. Old detail still exits with replacement semantics, never applying its cursor to new source buffers.

Rejected alternatives: temporarily focusing the reader and restoring focus emits disruptive window events; simulating keypresses uses cursor-dependent selection and can move sources; a separate automatic renderer duplicates the existing layout and cleanup.

### 4. Keep inference policy unchanged

Only existing `diff.auto_explain`, explicit requests, or already-owned work can supply missing notes. Consume eligible intent when those results become valid; never launch work to satisfy it. Keep restoration/cached-ready status and empty/failed/stale states honest. Review completion can supply selected File notes without switching the user back to Review or interrupting manually selected detail.

## Risks / Trade-offs

- [Source replacement races teardown] → Capture expanded state before automatic cleanup, bind it to the target, and exercise delayed coherent-buffer transitions with real Diffview.
- [Late results reopen obsolete or manually collapsed detail] → Consume intent once and retire it on navigation/user choices/terminal lifecycle events; test callbacks delivered after supersession and closure.
- [Programmatic events look like user choices] → Respect existing rendering/synchronization guards and validate with delayed restoration, not just immediately available notes.
- [Focus or source jumps] → Suppress focus transfer in the existing detail implementation and compare source views before/after automatic opening, including an off-screen first note.
- [Existing restoration assertions assume overview] → Change only assertions covered by expanded navigation; keep collapsed, empty, Review, cleanup, and inference-count coverage unchanged.
- [Rapid navigation crosses an unresolved target] → The later navigation uses actual collapsed state, not inherited pending intent. This is deliberate: continuity is not a sticky mode.

## Migration Plan

No configuration, cache, or data migration is needed. This is a default interaction change for an already-expanded diff reader. Update reading controls in README/UI help, run existing base and real-Diffview integration coverage, and visually inspect expanded-to-expanded and collapsed-to-collapsed navigation using offline fixtures. Reverting the implementation restores the previous always-collapsed file-navigation behavior without changing stored results.
