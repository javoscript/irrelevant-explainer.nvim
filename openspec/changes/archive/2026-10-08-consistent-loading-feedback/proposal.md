# Proposal

## Why

Saved-explanation checks currently look idle, and focused readers lose the header spinner even while work continues. Review loading over retained prose also leaves gaps on wrapped paragraphs, making cached-result validation appear inconsistently rendered.

## What Changes

- Show a header spinner for all user-visible busy phases, including saved-result checks, collection, cache lookup, external-agent work, review processing, and result-context validation.
- Keep the spinner animated when Explainr has focus and in expanded detail; preserve it in narrow headers whenever the essential mode/count/Auto and spinner fit.
- Show the buffer loader while checking saved file explanations, without inventing an inference request or decorating another file's ranges.
- Keep retained review content readable during repeated review requests and context checks, with a continuous loading rail across wrapped rows, blank lines, and empty viewport space.
- Freeze the focused logical line's gutter animation rather than removing its rail; keep text/backgrounds steady and the header spinner active.
- Preserve freshness validation, no-inference restoration, reading position, source isolation, and terminal-state cleanup.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Extend loading feedback to restoration/checking states, make Review rails wrap-aware, and replace focused-header spinner suppression with continuous busy indication.

## Impact

- `lua/explainr/session.lua`: Expose saved-result restoration and existing request ownership consistently to the UI.
- `lua/explainr/ui.lua`: Busy-state handling, timers, header clipping/detail ticks, review gutter rendering, and loader cleanup.
- `tests/ui_test.lua`, `tests/session_test.lua`, and `tests/diffview_test.lua`: Regression coverage for busy phases, cached review reuse, restoration ownership, screen-row coverage, and reading-state preservation.
- `tests/visual.lua` and the existing `tests/render.py` workflow: Representative loading-state captures.
- `README.md` and `doc/explainr.txt`: Update loading/focus behavior descriptions.
- No new dependencies, commands, configuration options, provider calls, cache-format changes, or request/freshness semantics. The existing focused-row/header pause policy changes intentionally.
