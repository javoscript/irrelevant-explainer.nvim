# Design

## Context

See proposal.md for motivation and the aligned-explanation-ui delta for the contract. `pane:show_review()` in `lua/explainr/ui.lua` saves pane-local options in `review_options`, switches to the narrative buffer, and enables native wrapping and linebreak. Review has no plugin-owned Ctrl-e/Ctrl-y handlers, and source-linked scrolling exits in Review mode. `smoothscroll` is currently inherited rather than set; its default is disabled.

Exploration on Neovim 0.12.5 used the real pane with a 45-column width and long paragraphs. Native Ctrl-e/Ctrl-y moved eight screen rows with smoothscroll disabled and one with it enabled; counted inputs moved the corresponding screen-row count with it enabled. The source viewport stayed unchanged. This establishes the reproduced case, not exhaustive verification of every boundary or supported version.

## Goals / Non-Goals

**Goals:**
- Use Neovim's own wrapped-line scrolling and the existing pane option lifecycle.
- Retain native count, cursor-visibility, and buffer-limit handling.
- Keep clipped wrapped reading positions compatible with the existing view save/restore mechanism.

**Non-Goals:**
- No new scrolling helpers, custom keymaps, global defaults, or configurable scrolling mode.
- No changes to File overview or detail scrolling, j/k movement, mouse-wheel step size, or page/half-page commands. Other native Review scrolling commands may naturally inherit smoothscroll's behavior; do not override them.

## Decisions

### Enable smoothscroll only while Review owns the pane

Include `smoothscroll` in the extra options captured by `show_review()` before changing the pane. Set its window-local value to true alongside wrap and linebreak, before restoring `review_view`. Let `show_file()` restore the previous value through its existing option loop. Do not add it to the shared base options table: doing so could change File defaults or overwrite the value before it is captured. Preserve both previously-disabled and previously-enabled settings.

Native smoothscroll avoids reimplementing word wrapping, gutters, counts, and limits in custom Ctrl-e/Ctrl-y callbacks. Existing Review showbreak spacing already accounts for native smoothscroll's continuation marker and should remain unchanged. Changing the source or global option would unnecessarily affect unrelated editor behavior.

### Preserve the native wrapped view

Continue saving the complete `winsaveview()` result, including `skipcol`, when leaving Review. Enable smoothscroll before `winrestview()` on reentry so the saved partial first line is representable. Do not normalize a saved view to a buffer-line boundary or reset unchanged narratives.

### Test observable screen movement, not just the option

Use the existing `tests/ui_test.lua` pane setup and input helpers. Add one focused scrolling regression using a narrow pane and uneven paragraph lengths, with a visible marker below the wrapped content to measure actual screen-row displacement. Exercise both directions, counts across a wrap/blank-line boundary, and unchanged source views. Extend existing Review lifecycle coverage for restoration of initially false/true smoothscroll and a round trip with nonzero skipcol. Assert the exact retained view as well as continued one-row scrolling after reopening; an option-only assertion would miss viewport regressions.

Validate native limits, busy retained prose, and rendering with the first visible row clipped inside a paragraph. Inspect idle and busy gutter coverage after rendering; do not add a new test per internal function or alter the loader.

## Risks / Trade-offs

- Native smoothscroll can affect other scrolling commands in Review → Accept native behavior rather than layering special-case mappings; retain File's original setting.
- Option leakage or loss of clipped position across mode switches → Save the prior option explicitly and cover both prior values plus a nonzero-skipcol round trip.
- Screen geometry depends on width, gutters, and redraw → Use settled rendered positions and independently expected row deltas, rather than assuming skipcol is a fixed multiple of window width.
- Exploration covered Neovim 0.12.5 only → Run the project's UI tests on the supported environment and exercise the boundary cases before declaring implementation verified.

## Migration Plan

No data migration, configuration change, or new dependency is needed. Deploy with the normal plugin update. Rollback restores the prior Review option setup and matching tests/docs; no persistent state is introduced.
