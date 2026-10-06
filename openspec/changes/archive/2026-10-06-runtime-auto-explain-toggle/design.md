# Design

## Context

See `proposal.md` for motivation and the delta specs for the behavior contract. `lua/explainr/init.lua` owns defaults, setup validation, the public Lua API, and commands; `plugin/explainr.lua` registers commands without setup. Setup rebuilds configuration from defaults, so using setup to toggle could reset the configured agent and context.

`session.lua` owns a registry of sessions by tab. Its `follow()` path reads `config.diff.auto_explain` when coherent buffers arrive and again after saved-note validation fails. Those operations can finish after a toggle, so simply changing the boolean is not sufficient for every subsequent-navigation boundary.

`ui.lua` draws the overview header through `pane:state()`, which currently exits while detail is open. Expanded detail builds its header inside the detail-render path. Request status strings also control animation and are exposed as `vim.b.explainr_status`; they are not a suitable place to store the mode indicator.

## Goals / Non-Goals

**Goals:**
- Keep one source of truth for automatic mode while separating a setting change from navigation/request lifecycle actions.
- Refresh only header presentation when toggling, with no detail rerender or session restart.
- Make the indicator available before a diff snapshot finishes collecting and after navigation clears a snapshot.

**Non-Goals:**
- No new settings service, persistence layer, request-provenance tracking, default keymap, or automatic code-mode behavior.
- No rewrite of rendering, inference queueing, or Diffview navigation.

## Decisions

### 1. Toggle the existing configuration in place

Add `toggle_auto_explain()` beside the existing public controls and register `ExplainrToggleAutoExplain` through the existing command pattern. Invert only `M.config.diff.auto_explain`, return its new value, and issue a short informational notification. Preserve setup's existing reset-to-defaults behavior when explicitly called again.

Do not call setup, Cancel, Refresh, or request entrypoints as part of toggling. A separate runtime setting would duplicate the flag already read by navigation. Do not eagerly load the session/UI/Diffview modules when no sessions exist; an already-loaded session module can propagate changes to its owned panes.

### 2. Preserve the navigation boundary through deferred work

Record automatic-request eligibility for each newly followed review entry using the mode at navigation detection. At both unexplained-file and stale-restoration request boundaries, require that eligibility and the current enabled setting. Disabling also revokes outstanding navigation eligibility so an off/on cycle cannot resurrect deferred work from an earlier navigation. Enabling does not reset `restoring`, re-follow the current file, or mark existing entries eligible.

This small session-local lifecycle field is necessary because saved-note checking, buffer loading, and background-tab activation are deferred. Relying only on the current boolean could request an earlier file when enabling mid-check. Cancellation or provenance flags on every request would instead change already-started/manual work unnecessarily. Existing generation/ownership guards and current-tab deferral remain authoritative.

### 3. Let sessions propagate mode to their owned panes

Use the existing session registry to update all nonclosed diff panes, without changing the current tab or window. Supply the pane's automatic-mode presentation state from the session's known mode and live configuration, rather than inferring diff mode from `pane.snapshot`: snapshots can be absent during collection or file switches. Initialize the same presentation state for newly opened diff panes, including those created after toggling with no sessions open.

Keep this propagation small and within the existing modules. It must update header presentation and deferred eligibility only, not request generations, queues, snapshots, notes, or timers.

### 4. Make header updates work in either reading mode

Extend the existing header-update ownership in `ui.lua` so overview and expanded detail can refresh their winbar independently of content rendering. Reuse that path from ordinary state/detail rendering and runtime propagation; do not call detail expansion, collapse, or full `pane:render()` just to change `Auto`.

Place muted `Auto` immediately after the count and before request/detail descriptions, for example `Explainr · 2 / 5 · Auto · Ready` or `Explainr · 2 / 5 · Auto · Expanded`. Reserve the count/indicator budget before lower-priority title, context, legend, or hints; retain existing semantic colors and literal-text escaping. Extremely narrow panes remain width-clipped, with counts prioritized if both cannot fit.

Do not decorate `pane.status` or `vim.b.explainr_status`: that would alter public request-state semantics and could affect Pending animation or matching. Do not modify the user's statusline or add content rows.

### 5. Verify transitions and actual headers with existing offline fixtures

Extend setup/API tests for both entrypoints, defaults, return values, notifications, preservation of asymmetric custom configuration, and no dependency loading when no pane exists. Use Diffview/session fixtures to count agent calls across off/on navigation, delayed buffer/restoration completion, background deferral, active requests, and manual queued hunks. Keep paid inference out of verification.

Extend UI tests to evaluate visible winbar text and compare detail buffer identity, selected note, cursors, views, focus, request status, and user statuslines before/after toggling. Use enabled and disabled states, both reader modes, narrow panes, and multiple tabs. Render representative enabled overview/detail/narrow headers and a disabled comparison through `tests/render.py`, then inspect the captures rather than relying only on string assertions.

## Risks / Trade-offs

- Deferred work can accidentally trigger inference after enabling → Test both saved-note failure and coherent-buffer/tab-activation delays; gate both automatic entrypoints by navigation eligibility and current mode.
- Background or expanded headers can remain stale → Update through the registry and a header-only path that supports either reader mode, without changing focus.
- New text can crowd out counts or mislead users about a running job → Budget `Auto` alongside counts and document that it describes mode, not request provenance or activity.
- Disabling does not stop an already-started request → Preserve existing request lifecycle and document `ExplainrCancel` as the explicit stop control.

## Migration Plan

No data migration or configuration changes are required. Existing users retain their setup value and default-off behavior; the new command/API are additive. Removing the new toggle and indicator restores the previous interface without persisted state to clean up. Documentation will include a user-defined `<leader>ea` mapping example rather than installing it.
