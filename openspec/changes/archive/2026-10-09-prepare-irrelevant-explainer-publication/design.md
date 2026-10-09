# Design

## Context

See `proposal.md` for motivation and `specs/` for the observable contracts. The plugin currently loads through `plugin/explainr.lua` and `lua/explainr/`, registers commands in `init.lua`, and publishes Explainr-prefixed highlights, the `explainr` filetype, and `vim.b.explainr_status` through `ui.lua`. Semantic cache identities are built in `identity.lua`; `cache.lua` owns private storage at `stdpath("cache")/explainr/results/v1`.

`init.lua` already exposes `ai.command` as arbitrary argv and `ai.output` as plain/OpenCode/Codex/custom decoding, but defaults to an empty command and plain output. Its existing `vim.tbl_deep_extend` setup merge replaces list-valued options completely; a read-only Neovim probe confirmed both a one-element command override and an explicitly empty list replace the proposed six-element OpenCode default.

The README has detailed behaviour and privacy documentation but only local-checkout installation. No license, shared ignore rules, CI, or remote is present. Existing local edits and another completed OpenSpec change are outside this change's ownership and must not be overwritten. The initial exploration found no credential-pattern matches in 156 current files and 333 unique historical blobs reachable from 25 commits; that is preliminary evidence, not the required dedicated scan or manual privacy clearance.

Offline tests run through `tests/run.lua`, isolate their cache, and use fake processes. Diffview/command/persistence integration tests conditionally skip when the optional runtime is absent. `tests/render.py` records Neovim's real screen grid and can encode GIFs, but currently launches with `-u NONE`; `tests/visual.lua` forces a default theme and artificial statusline. The author's personal Neovim configuration and installed plugin runtime are available on this runner. Current capture tooling therefore needs an explicit opt-in mode for the requested personal styling.

## Goals / Non-Goals

**Goals:**
- Make one coherent public identity change, adopt explicit OpenCode setup defaults, and preserve transport, selection, diff ownership, and wire protocols.
- Keep installation and demo assets self-contained for GitHub readers while presenting personal work rather than a product.
- Make privacy clearance and verification evidence reviewable before any external publication action.

**Non-Goals:**
- Compatibility aliases for the old public package or commands, a cache migration framework, new provider features, or a marketing site.
- Editing personal dotfiles, disturbing an existing Neovim session, recording private repositories, or using real provider calls for demonstrations.
- Shipping automatically, rewriting history for cosmetic branding, or promising continuing support.

## Decisions

### 1. Rename the public identity in place, without aliases

Use the technical identifiers proposed in the proposal:

| Surface | New identity |
| --- | --- |
| Repository | `irrelevant-explainer.nvim` |
| Lua module tree and reader filetype | `irrelevant_explainer` |
| Loader | `plugin/irrelevant_explainer.lua` |
| Load guard | `vim.g.loaded_irrelevant_explainer` |
| Commands and highlight prefix | `IrrelevantExplainer` |
| Display-only action | `<Plug>(IrrelevantExplainerReview)` |
| Status integration | `vim.b.irrelevant_explainer_status` |
| Help entry and tag prefix | `irrelevant-explainer.txt`, `irrelevant-explainer` |
| Test environment prefix | `IRRELEVANT_EXPLAINER_` |

Preserve command suffixes, public Lua method names, setup options, and supported scopes. Update internal requires, namespace/augroup/buffer-variable names, statuscolumn/fold expressions, fake-agent paths, test child-process environment handoff, fixture outputs, help links, and current public examples together. Do not rename the external user-created `explain` agent or provider CLI flags: those are not this plugin's package identity.

A display-only rebrand would leave two names competing in installation and configuration. Aliases would add maintenance machinery for a private, unpublished predecessor. A clean breaking rename with a short migration table and restart guidance is simpler. Archived OpenSpec changes and existing Git history remain historical records. Lexical name references in current main specs can be aligned during implementation without changing unrelated requirements; the delta blocks here define the changed contracts.

### 1.1. Default to OpenCode, keep the existing transport option

Set setup defaults to:

```lua
ai = {
  command = { "opencode", "run", "--agent", "explain", "--format", "json" },
  output = "opencode",
  timeout_ms = 300000,
}
```

Keep `ai.command` and `ai.output` as the source of truth; no new provider selector, shell-string option, wrapper, or configuration adapter is needed. Reuse the existing list-replacement merge rather than append/merge argv elements. `{ "my-wrapper" }` must remain exactly that one argument; explicit `{}` still permits setup but cannot start inference. Setup without overrides resets to defaults and must not mutate caller-owned option tables.

Changing the command alone does not guess an output format: `ai.output` remains opencode unless explicitly overridden. Document Codex with `{ "codex", "exec", "-", "--json", "--sandbox", "read-only" }` and `output="codex"`, a compatible wrapper with `output="plain"`, and the existing custom-decoder contract. Preserve `cache.decoder_key` guidance for custom decoder disk reuse. Arbitrary executables still have to consume the structured prompt and return a compatible payload; configurability is not a promise that any CLI works unmodified.

OpenCode must be installed and authenticated, with the user-created restricted `explain` agent and provider/model configured externally. Do not hard-code a provider/model, introduce automatic installation/login, or add fallback/approval flags. The existing missing-agent warning/fallback caveat in OpenCode guidance remains important: this default does not enforce the external agent's existence or permissions. Loading/setup do not spawn an agent, and demonstrations/tests explicitly configure fake commands and compatible output decoders so the new defaults cannot launch live OpenCode.

A default only for documentation would not meet the requested initial behaviour. Keeping the empty command as default would force boilerplate on the common OpenCode path; automatic decoder inference would create surprising executable-name heuristics. Explicit paired defaults and overrides are simpler and preserve user ownership.

Extend existing setup/session/transport tests for exact defaults, one-element argv, empty argv, paths/arguments with spaces and shell syntax, command-only versus paired decoder overrides, setup reset/caller-table isolation, missing executables, and unchanged plain/Codex/custom decoding. Test observable configuration and offline results, not implementation-specific merge calls. Existing plain fixture commands must explicitly choose plain output where they previously inherited it.

### 2. Retain the existing cache storage path intentionally

Keep `explainr/results/v1` as a documented internal compatibility exception. The semantic key does not include the public plugin package or command prefix; preserving generation inputs, wire data, and format/planner/prompt versions avoids branding-only invalidation. Rename imports and diagnostics, not semantic generation instructions. Do not bump identity versions for cosmetic changes.

Automatic movement to a new cache tree would introduce locking, concurrent-reader, cleanup, and rollback complexity without a useful behavioural gain. Retaining the path means the renamed clear command still reaches old records. Validate continuity using a disposable pre-rename record and the renamed public API, including a nearby unrelated sentinel that must survive clearing. Never test against or clear the author's personal results. Users must restart instead of loading both identities concurrently.

Storage continuity does not override semantic generation identity: changing effective external argv or output decoder remains a normal cache miss. Pre-rename reuse tests must supply the same explicit AI configuration on both sides; the new default must not accidentally reuse an answer generated by a different command/decoder.

### 3. Put satire in editorial copy, not in technical behaviour

Open the README with the name, a sharp tagline, and a plain personal-use/showcase statement, followed by demonstrations and a short quick start. For example: "The agents write the code now. This plugin explains it to the people still insisting on being involved." This is draft copy, not a required exact string. Selected headings can share that voice without making the installation section hard to find.

Keep the detailed contracts in the existing help files and link to them rather than reproducing every edge case above the fold. Preserve clear source-transmission, agent-permission, plaintext-cache, and billing/compatibility warnings. No satirical instructions enter prompts, fixtures' explanatory content, or actionable error messages. Prefer a brief limitations/maintenance note over a support policy, roadmap, contribution bureaucracy, or release machinery.

### 4. Capture the personal editor on synthetic content

Extend the existing renderer/fixture ownership points rather than create a second capture stack. Add an opt-in personal-config mode that loads the author's real Neovim configuration, waits for its styling and needed plugins, and preserves its colorscheme, syntax, statusline, and visible editor styling. Keep default `-u NONE` test captures and forced test styling unchanged. For motion demonstrations, drive actual expansion, navigation, and scrolling between captured redraws; the existing animated loader loop alone is not sufficient.

Use a fresh disposable Neovim process, not the author's open session. Load the renamed checkout for that process without modifying personal plugin-manager files or allowing the old plugin copy to own the demo. Disable automatic plugin installs/updates, session restoration, startup dashboards/recent-file content, and unrelated live services in that process where necessary. Keep ShaDa, swap, backup, sessions, notifications containing private context, and Explainr result writes isolated or disabled. Installed theme/parser dependencies remain available; personal caches and saved results are not cleared. If config integration needs an override, make it process-local and document it, rather than replacing the personal theme with a test approximation.

Use synthetic Lua buffers and the existing disposable Git review fixtures with offline structured answers. Prefer neutral filenames and a public-safe disposable repository name so explorer, statusline, tabline, command echoes, and prose never need real project paths. Capture only the editor area, not the surrounding desktop or terminal history.

The minimal media set is:
- `doc/media/code-overview.png`: aligned current-code notes with an informative file overview.
- `doc/media/code-detail.gif`: actual expansion, a short synchronized navigation/scroll, and collapse.
- `doc/media/diff-overview.png`: old/new changes and aligned notes in Diffview.
- `doc/media/review-navigation.gif`: whole-change narrative, following a file reference, and returning to the narrative.

Use real UI output, not Painter or reconstructed screenshots. Add descriptive alt text and short captions stating that answers are fixtures. Crop/resize/compress for README legibility while keeping code and notes readable. Store only final approved assets under `doc/media/`. Raw captures, extracted frames, audit output, and contact sheets stay under excluded `.amp/in/`; inspected review artifacts belong in `.amp/in/artifacts/`. Confirm the repository-local exclusion before producing them.

Privacy review covers every screenshot and every distinct GIF frame, including transient startup/notification frames and final image metadata. Extract frames/contact sheets for review with `view_media`, and inspect the full animation; checking only its first frame is insufficient. Reject and recapture leaked content where possible; if cropping or sanitization is used, inspect the final encoded asset again. Never stage unsafe raw media. Text scans do not substitute for this visual audit.

### 5. Make CI small, offline, and explicit about optional integrations

Add a single workflow with base tests, Diffview integration, and secret scanning as separate jobs. Base jobs use Python/Git and the documented Neovim 0.11.5 and 0.12.5 versions, after verifying release availability. Pin downloaded tools and workflow actions to reviewed immutable versions. Integration jobs provide pinned Diffview and Plenary runtimes through renamed environment variables, verify those directories before testing, and fail if required integration coverage reports a missing-dependency skip. Use the documented Diffview revision as the starting compatibility pin; record the selected Plenary pin at implementation.

Use the normal headless startup command, not `-l`. Keep test caches disposable and fake agents mandatory. Markdown parsers and authenticated providers remain optional and are not implied by passing fixture tests. Do not run personal-config media capture in CI or upload the author's config. Workflows need only read permissions and no release/deployment steps or provider credentials. Prefer a pinned standalone scanner executable rather than a scanner action that requires an extra repository secret.

### 6. Audit both files and history before choosing what to publish

Use Gitleaks as the dedicated scanner, pinning a released version and verifying its file-scan and all-ref Git-scan CLI during implementation. Scan candidate file contents, including proposed untracked additions, and a nonshallow local repository containing all refs intended for publication. Include deleted historical blobs and commit/tag messages in the manual review as well as current docs, generated guidance, links, paths, fixtures, and binaries. Scanner results are redacted and raw logs are excluded. Test the scanner on a disposable synthetic repository containing a fake secret only in a deleted file to confirm history coverage; never add that fixture credential to this repository.

Record the scanner version, candidate revision/file set, ref inventory, commands, detected/suppressed findings with reasons, manual scope, media review, and limitations without copying sensitive values. Author/committer identity requires an explicit owner privacy choice; do not classify a work email as a credential. Review current ignore rules alongside the actual index: an ignore rule does not remove already-tracked content or older exposure.

Any discovered secret blocks external publication. Rotation and approved history/file cleanup are remediation, not scanner suppression. No broad allowlist is introduced to manufacture a clean result. Repeat the scan against the final staged/exported candidate and full intended history after documentation and media are finished. Local reflogs/dangling objects are not normally pushed, but do not use `--mirror` or publish unexpected refs; re-audit if the intended ref set changes.

### 7. Keep licensing and external actions as named gates

Recommend MIT for simple reuse, but obtain the owner's license/copyright approval and check provenance before adding legal text. The exact GitHub owner is also owner-supplied; local directory names are not evidence of an account. These choices do not change the technical rename or the task breakdown. Do not pretend placeholders are working installation coordinates.

Preparation ends with a verified candidate and a redacted readiness summary. Repository creation, visibility changes, pushes, credential rotation, and history rewrite require separate scoped approval. Preserve history unless a finding or explicit metadata decision justifies cleanup. Avoid releases, publishing packages, automatic tags, or deployment workflows for this personal showcase.

## Risks / Trade-offs

- [Longer brand crowds narrow headers] → Preserve existing measured-width clipping and priority order; inspect wide/narrow File, detail, Review, and pending states.
- [Missed runtime identifier or child-process environment breaks integration] → Use scoped residual-name searches and the complete offline suite; allow only documented historical/storage names.
- [OpenCode output default breaks wrappers or triggers real tools in tests] → Document paired command/decoder overrides, explicitly configure offline fixtures, and test default setup without launching inference.
- [Personal editor configuration leaks private chrome or performs startup side effects] → Use disposable synthetic sessions, process-local isolation, fixture answers, and all-frame inspection before staging.
- [Media maintenance and repository size] → Keep four short, focused assets and only final compressed versions; do not retain capture intermediates in Git.
- [A secret scanner misses private business context or binary content] → Manual file/history/metadata/media review remains required; report bounded evidence rather than a guarantee.
- [Publication cleanup overwrites concurrent local work] → Inventory and preserve existing edits; select an explicit candidate rather than staging the entire worktree indiscriminately.
- [Retained cache path looks inconsistently branded] → Document it as intentional storage compatibility instead of adding a migration layer.

## Migration Plan

1. Inventory the current worktree and publication refs; run the initial sensitive-information audit and surface license/metadata decisions.
2. Rename the runtime/public interfaces, set the OpenCode command/decoder defaults, and adapt existing tests with explicit fixture decoders, retaining cache semantics and generation contracts.
3. Update practical documentation and editorial copy, add approved legal/ignore metadata and CI, and capture inspected personally styled media.
4. Validate from a clean disposable candidate with no user configuration for ordinary tests, inspect UI/media using the personal capture mode, and repeat the complete publication audit.
5. Report local delivery state and request specific external actions only after the candidate clears the gates. Do not create or publish a remote during preparation.

Before publication, rollback is a local return to the previous checkout plus restoration of personal mappings by the owner; retained cache storage needs no rollback migration. After publication, prefer ordinary follow-up commits; history rewriting requires its own approval and coordinated remediation.

## Resolved Owner Decisions

- License: MIT, with copyright attribution `2026 javoscript <javougarte@gmail.com>`.
- GitHub coordinates: `javoscript/irrelevant-explainer.nvim`.
- Public metadata: preserve author/committer names and email addresses; private Amp thread references must not be published.
- Historical sanitization: the owner approved neutral replacements for identifying fixtures and removal of private Amp thread references. That local sanitization is complete; author/committer identities and timestamps were preserved.

These decisions do not authorize external repository creation, pushes, visibility changes, further history rewriting, or deletion of the excluded original-history recovery material. Those actions remain separate approval gates.
