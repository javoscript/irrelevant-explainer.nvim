# Design

## Context

See `proposal.md` for motivation and `specs/aligned-explanation-ui/spec.md` for the behavior contract.

`lua/explainr/ui.lua` currently makes two decisions independently: `pane:overview_header()` reserves blank source winbars only when a result contains an overview note, while `pane:state()` uses either the source-matched winbar or a first-content-row overlay. The overlay chooses one state-specific highlight for the entire label; the winbar has no explicit segment highlighting. `pane:detail()` builds another plain-text winbar and has a separate no-winbar count fallback.

Source ownership already includes the followed window plus snapshot, pending, and queued windows. Placeholder cleanup already restores only a still-owned blank value, preserving user replacements. Existing intent mappings define the exact groups used by summary and detail markers. Counts, queued state, focused-context labels, and loading animation already have working ownership paths and remain authoritative.

## Goals / Non-Goals

**Goals:**
- Make header reservation a pane-lifecycle concern rather than a result-content concern.
- Give overview and expanded headers consistent explicit foreground styling while retaining their existing content differences.
- Preserve source display geometry and decoration-only spinner updates.

**Non-Goals:**
- Redesign content layout, expanded navigation, loading rails, or the editor's statusline.
- Add a header-position setting, external renderer, fixed RGB palette, or generic formatting framework.
- Implement the separate `sync-expanded-prose-cursor` change.

## Decisions

### 1. Generalize the existing matched-winbar lifecycle

Reserve matching blank winbars for owned sources before the initial projection/render even when no result exists. Keep those reservations while the pane remains open, including when results are cleared. Reconcile ownership when sources change; release tracked placeholders on ownership loss and closure only if their value is still the plugin's blank sentinel. Continue leaving nonempty user source winbars untouched. If an owned source's winbar is cleared during an active pane, re-reserve the blank matching row through the existing update lifecycle.

Use a native winbar for the explanation pane rather than adding virtual rows or a floating header. Virtual rows would require an unmatched offset and complicate filler/wrap navigation; a float would introduce unnecessary geometry and lifecycle work. The native matched header already solves the alignment problem for file overviews.

Remove the now-unreachable content-status paths: overview `virtual_status` and its loading-row injection, state-overlay placement, and expanded no-winbar count fallback. Retain unrelated detail/range/loading decorations. Rename the overview-specific reservation method if needed to reflect its broader responsibility; do not add a parallel reservation layer.

### 2. Style semantic segments in the existing winbar rendering

Represent header text as semantic segments and serialize native winbar highlight switches only after measuring and clipping visible text. Use `ExplainrMetadata` for counts, spinner, state, queue/context text, descriptions, separators, and expanded hints. Reuse the existing `intent` mapping for D, ~, and ?; explicitly return to muted styling after each marker.

Introduce a title-specific `ExplainrTitle` default link to `DiagnosticInfo`, using the same default-only registration pattern as the other groups. This keeps the theme's cyan/information accent and gives users a stable title override without tying the title to request-state highlights. Do not select a header-wide group from the current status. Remove old state-color group definitions if no consumers remain after removal of the overlay path.

Keep formatting local to `ui.lua`. Share only the minimal serialization needed by overview and expanded header paths, rather than duplicating escaping/clipping or introducing a reusable UI subsystem. Escape literal percent signs in every dynamic text segment and use display-cell width for multibyte text; highlight control sequences must not consume the visible width budget. Reset styling at the end of the header so padding does not inherit an intent marker's color.

Preserve current count-first width prioritization, abbreviated legends, and omission of the title when space is insufficient. Whenever `Explainr` is visible, it uses the title group. Keep the expanded header compact: it retains counts and navigation hints rather than gaining the overview legend or focused-context warning.

### 3. Verify screen geometry and evaluated highlights, not raw option strings alone

Adapt existing tests that expect content overlays or restoration on overview disappearance. Add pending-to-ready screen-row assertions with and without overview notes, mixed source winbars in a two-sided diff, stale/clear-result lifecycle, and expanded/collapsed transitions. Use distinct custom semantic colors and evaluated winbar highlights to detect a whole-label color or a missing muted reset; raw `%#...#` substrings alone are insufficient.

Exercise narrow and wide headers, literal `%` status text, multibyte clipping, and terminal states. Preserve the existing spinner test's no-buffer-change/no-full-render assertions, count/navigation behavior, and lualine/statusline ownership checks. Capture and inspect representative rendered pending, ready, and expanded states during implementation.

## Risks / Trade-offs

- [One screen row is consumed when opening beside sources without headers] → Reserve it once at opening; document that no later result/state transition adds or removes it.
- [Header changes can schedule redundant alignment events] → Reuse existing update guards and only assign changed winbar values; spinner ticks must remain decoration-only.
- [A colored winbar can mismeasure text or interpret percent escapes] → Clip semantic text before serialization and check evaluated visible text/highlight spans at narrow widths.
- [User source-header edits may be overwritten on cleanup] → Preserve the existing sentinel-value ownership check and cover replacement headers in regressions.
- [The separate prose-cursor change edits the same UI file and tests] → Keep this change confined to reservation/formatting and rerun the combined UI suite if both changes are applied.

## Migration Plan

No configuration or data migration is required. Update UI documentation that describes first-row status overlays and overview-dependent placeholder restoration. Existing user statusline integrations through `vim.b.explainr_status` remain unchanged. Reverting the UI and documentation edits restores the old behavior without a migration.
