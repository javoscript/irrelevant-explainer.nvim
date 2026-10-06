# Design

## Context

See `proposal.md` for motivation and the delta spec for behavior. A design is warranted because changing movement semantics intersects sticky scrolling, partial wrapped lines, optional highlighting, and another active change in the same UI owner.

`lua/explainr/ui.lua` owns both buffers. The overview already registers `explainr` with the Markdown parser. Detail instead sets filetype `markdown`. The `markdown()` helper invokes render-markdown.nvim for both, seeds per-buffer options, and provides refresh callbacks. Detail uses conceallevel 3, native wrap/linebreak, and cursor/scroll/mode refresh hooks. `detail_reflow()` detects height changes so layout corrections are not forwarded as reading scrolls.

Detail has no built-in j mapping. Its k callback either performs the top-edge scroll fallback or executes native buffer-line k. Existing wrapped-prose tests explicitly use gj/gk, so they do not establish the desired j/k behavior. A clean Neovim 0.12.5 reproduction without plugins moved from screen row 1 to 5 with j and to row 2 with gj on a four-row paragraph. This proves an independent navigation issue, not that the renderer caused the user's entire symptom.

The active `sync-expanded-scroll-cursor` change corrects final source selection after reader scrolling. Preserve its changes and tests. This proposal deliberately adds a separate navigation requirement instead of replacing that change's full scrolling requirements at archive time.

## Goals / Non-Goals

**Goals:**
- Keep syntax coloring separate from display geometry using the existing buffer lifecycle and semantic marks.
- Let native displayed-row motions handle wrap widths and desired columns while the existing synchronization owner handles source selection and scrolling.
- Remove renderer-specific ownership without deleting geometry handling still needed for resize, wraps, folds, or diff filler.

**Non-Goals:**
- A new rendering abstraction, custom Markdown grammar, manual line reflow, hard-wrapped buffer text, or native-syntax fallback subsystem.
- Broad changes to sticky layout, source projection, scrolloff normalization, other normal-mode keys, visual/operator-pending mappings, or user source options.
- Suppressing arbitrary third-party plugins explicitly configured by the user to target `explainr`.

## Decisions

### 1. Use one filetype with optional Markdown highlighting

Retain the existing `vim.treesitter.language.register("markdown", "explainr")` association and guarded `vim.treesitter.start(buf, "markdown")` startup for both buffers. Set detail to `explainr` before starting highlighting. Native Markdown queries provide `markdown_inline` and fenced-language injections when those parsers exist; no custom source-language injections are needed.

Set conceallevel 0 explicitly in the owned explanation window, including lifecycle transitions, so inherited settings cannot hide Markdown punctuation. Preserve existing wrap/linebreak and overview-option restoration. Keep current semantic marks as the parser-free fallback rather than adding another highlighting engine. Do not install parsers or alter global syntax, renderer, or conceal settings.

**Alternatives:** plain-text output loses useful structure without fixing j/k; retaining filetype `markdown` invites ordinary Markdown filetype integrations; adding native `syntax=markdown` is possible but adds a second highlighting path unnecessarily for this change.

### 2. Remove the renderer integration, not Explainr's own layout

Remove the renderer loader/config helper, summary/detail refresh callbacks and their call sites, renderer-only autocmds, and renderer callback state from cleanup. Preserve semantic colors, focus surface, header/range controls, and context decorations. Visible Markdown markers remain part of native text width; headings, lists, and code fences no longer receive renderer padding, replacement glyphs, or hidden rows.

Retain `detail_reflow()` and shared display-height measurement where they still protect native geometry corrections. Remove only demonstrably renderer-exclusive behavior; a renamed comment is not evidence that a geometry guard is obsolete. Do not call renderer disable/setup APIs, since those would reintroduce dependency ownership or affect user buffers. Ordinary renderer attachment to `markdown` no longer sees Explainr buffers; explicit user configuration targeting `explainr` is outside this guarantee.

**Alternative:** retaining a renderer opt-in mode preserves two display-geometry paths and their testing burden. The agreed direction is one reader, not another configuration switch.

### 3. Map expanded j/k to native displayed-row movement

Install normal-mode buffer-local j and k callbacks alongside the current detail mappings. Execute native counted gj/gk without remapping, then reuse the existing reading synchronization path. Counts always mean display rows; do not retain the common conditional mapping where only uncounted motions use gj/gk. Native gj/gk remain available unchanged.

For k, preserve the existing shortcut only when the cursor is on the summary's first displayed segment and that segment is at the top content-screen edge. Check the segment using native display geometry, not merely buffer line identity, byte column zero, or winline equal to one: a later wrapped segment can be scrolled to the top with skipcol. From any later segment, execute ordinary counted gk; do not synthesize a second shortcut after the motion. Starting on the actual top-edge first segment forwards the full requested count to the existing upward-scroll path.

Do not add a second source-target algorithm. Preserve the completed-scroll behavior owned by `sync-expanded-scroll-cursor`, including focus, source views, native limits, and settled snapshots. Existing movement into outside context must still collapse at its destination.

**Alternatives:** relying on global j/k mappings gives inconsistent behavior and the current local k already bypasses them; rewriting prose into screen-width lines makes resizing mutate text and destabilizes positions.

### 4. Verify the changed contracts rather than renderer implementation details

Replace renderer-seeding tests with no-renderer-call, filetype, concealment, and fallback assertions. Adapt optional installed-runtime tests to check actual syntax highlighting and renderer isolation, not renderer namespace marks. Keep JSON quote/backslash preservation coverage unconditional. Test missing root and injected parsers without deriving expected output from the code under test.

Use real mapped input for j/k tests, not normal! j/k or explicit gj/gk. Use asymmetric paragraphs whose known width creates multiple rows, test both directions and counts across a blank line, and distinguish a wrapped summary's first segment from a later segment clipped to the top. Preserve native-limit and global-map isolation checks. Extend existing geometry fixtures for source wraps, folds, and deletion filler rather than multiplying every combination.

Use the existing Neovim screen-grid captures for narrow/wide detail containing a heading, inline code, a fenced snippet, and wrapped text, plus a wrapped summary/top-edge reading state and collapsed overview. Inspect actual captures with and without optional syntax support. Installed-renderer checks must also show that an ordinary Markdown buffer remains under user renderer control.

## Risks / Trade-offs

- [Visible Markdown markers increase card height] → Accept native wrapping and retain layout measurement, sticky positioning, resize, and current-position collapse checks.
- [A later wrapped summary segment looks like the top-edge summary] → Assert the partial-wrap/skipcol boundary explicitly before using the scroll shortcut.
- [Removing callbacks removes needed geometry correction] → Keep native height/reflow guards unless focused tests demonstrate they are renderer-exclusive.
- [Other filetype integrations stop attaching to detail] → Document the deliberate change from `markdown` to `explainr` and keep Markdown parser association separate from filetype identity.
- [Optional parsers differ across installations] → Keep dependency-free semantic fallback tests mandatory; exercise richer syntax when installed and report missing optional coverage honestly.
- [Concurrent changes touch ui.lua and its tests] → Integrate against the completed or current scrolling correction without overwriting it; serialize edits to shared files and run combined regression coverage.

## Migration Plan

No data, model prompt, or public configuration migration is needed. Update documentation to remove optional-renderer setup claims and describe the new filetype, visible markers, parser fallback, and display-row counts. Users can keep their renderer installed for ordinary Markdown; they need not change global mappings.

Implement renderer removal and native presentation first, then displayed-row mapping behavior, with focused tests at each stage and full editor/visual verification afterward. The existing main-spec decision that rendering is optional compatibility is superseded by the new renderer-free requirement; reconcile that descriptive decision when syncing or archiving this delta. Keep the scrolling change's spec additions intact regardless of archive order. Rollback reverts only this change, retaining unrelated cursor-sync and runtime-toggle work.
