# Proposal

## Why

Explainr initially paints loading status over the first content row in an accent color, then moves it into a muted header when a file overview arrives. A stable header with consistent semantic colors avoids that visual jump and makes the intent legend match the explanations it describes.

## What Changes

- Reserve a separate explanation header as soon as the pane opens, regardless of whether results or a file-overview note exist. Keep it throughout loading, ready, refresh, failed, stale, cancelled, and expanded-detail states.
- Keep `Explainr` in the theme's cyan/accent color; render counts, spinner, state, separators, legend descriptions, and expanded navigation hints in muted text from the start. Status transitions change text, not the palette.
- Render legend symbols `D`, `~`, and `?` with the same semantic highlight groups as their explanation-item markers.
- Preserve aligned content rows by reserving temporary blank winbars in paired source windows that lack one. Restore owned placeholders when a source leaves the pane's ownership or the pane closes, while preserving existing headers and user edits.
- Retain existing counts, focused-context information, spinner behavior, compact expanded header, and narrow-width prioritization without taking ownership of the editor's statusline.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Replace result-dependent header placement and first-content-row fallback status with a persistent matched header and state-independent semantic text colors.

## Impact

- Header lifecycle, state rendering, legend highlighting, and expanded header rendering in `lua/explainr/ui.lua`; regressions in `tests/ui_test.lua`; behavior descriptions in `README.md`, `doc/explainr-ui.txt`, and `doc/explainr.txt`.
- Opening a pane beside sources without winbars reserves one screen row immediately; receiving or invalidating explanations no longer changes that reservation.
- The existing spec's non-overview overlay fallback and tests restoring blank headers on overview disappearance must be updated explicitly.
- No new dependencies, configuration, mappings, inference calls, source-buffer changes, or changes to native diff membership. Expanded prose cursor synchronization is a separate change and is out of scope.
