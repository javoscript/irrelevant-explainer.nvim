# Proposal

## Why

Publish this personal-use Neovim plugin as inspiration and a showcase, not as a supported product. Rename it **Irrelevant Explainer** and give the repository an acidic, self-aware voice: in the age of AI and agentic development, understanding the code is apparently obsolete, so here is an entire plugin devoted to that futile activity.

## What Changes

- Make the personal origin and showcase purpose prominent in the README. Publication is an invitation to inspect, borrow ideas, and adapt the code, not a promise of support, stability, a roadmap, or broad compatibility.
- **BREAKING**: Replace the Explainr package identity with Irrelevant Explainer. Proposed technical names are `irrelevant-explainer.nvim` for the repository, `irrelevant_explainer` for Lua imports, and `IrrelevantExplainer` for the command prefix. Rename runtime entrypoints, public integration identifiers, help tags, UI branding, current documentation, and examples consistently; document migration for the existing personal configuration.
- Give the README introduction, tagline, and selected headings dry, acidic humour about outsourced understanding, agentic hype, and this plugin's lovingly engineered irrelevance. Suggested tagline: "Explanations for code nobody needs to understand anymore." This is satire, not a factual claim that comprehension is unnecessary. Aim the joke at the premise and the project itself, not at users.
- Keep installation, technical help, diagnostics, security/privacy warnings, and generated code explanations accurate and actionable. Branding must not turn explanation prompts into comedy or weaken grounding, validation, cancellation, or source isolation.
- Default `ai.command` to `{ "opencode", "run", "--agent", "explain", "--format", "json" }` and `ai.output` to `"opencode"`, retaining the 300000 ms timeout. Preserve the existing arbitrary executable/argument-list option: custom argv replaces the entire default list, and users can choose OpenCode, Codex, plain, or custom output decoding. Document restricted-agent prerequisites and alternate-tool examples; do not install/authenticate tools, guess decoders, or add automatic provider fallback.
- Include README screenshots and GIFs demonstrating aligned code/diff notes, expanded detail and synchronized navigation, and whole-review narrative/file navigation. Capture the running plugin using the author's personal Neovim configuration for styling, with synthetic public-safe content and offline fixture explanations only. Inspect every published image and GIF frame, including editor chrome and metadata, for sensitive information before adding the media to the repository.
- Prepare a minimal public repository: an explicitly chosen license with attribution review, shared ignore rules, GitHub installation instructions, a concise quick start, and reproducible offline CI with explicit Diffview integration coverage and ongoing secret scanning. Keep detailed help available without turning the showcase into a product launch.
- Treat sensitive-information review as a publication gate, covering repository files **and complete commit history**, including deleted content, all branches/tags, commit messages, author/committer metadata, and annotated tags. Use a dedicated secret scanner with redacted output plus manual review for private documents, internal links, paths, fixtures, and images/binaries. Review the existing author email as a separate privacy decision; a pattern scan alone is not proof of safety.
- If sensitive material is found, stop publication, rotate exposed credentials where applicable, and agree on cleanup before rewriting history. Preserve history unless findings or an explicit privacy decision require sanitization; do not silently rewrite historical branding or archived development records.
- Before publishing, reconcile existing local work, validate installation/help and renamed interfaces from a clean checkout, run the offline suite, inspect renamed UI states, and repeat the sensitive-information audit on the final candidate. GitHub repository creation, remote configuration, pushes, and any history rewrite remain explicit approval steps, not automatic consequences of this proposal.

## Capabilities

### New Capabilities

- `repository-presentation`: Public identity, personal-use/showcase positioning, and satirical editorial voice with clear practical documentation and no implied support commitments.

### Modified Capabilities

- `code-explanation`: Rename the public Lua package and explanation/control commands while preserving scopes, routing, and selection semantics.
- `diff-explanation`: Rename review, refresh, and automatic-explanation entrypoints without changing comparison ownership or inference behavior.
- `aligned-explanation-ui`: Rename visible branding, reader filetype, public styling/status identifiers, and pane-local actions while preserving rendering and navigation contracts.
- `external-agent-execution`: Default to OpenCode command/event decoding, preserve complete custom argv/decoder overrides, and align public cache controls with the new identity while preserving transport, validation, and private-storage guarantees.

## Impact

- Runtime modules and loader under `lua/` and `plugin/`, public commands/imports, UI integration names, tests/fixtures, README, help files, and current specs. Existing personal mappings, theme overrides, and status integrations need migration.
- Rename design must explicitly address existing cache ownership and clear behavior without deleting unrelated data or silently losing access to old plugin-owned records.
- Setup without AI overrides now selects OpenCode rather than an empty command/plain decoder. OpenCode remains a replaceable external tool, not a mandatory dependency for plugin loading or custom transports; existing plain-output wrappers must explicitly select `ai.output="plain"`.
- New repository metadata and CI tooling; no change to the explanation wire protocols is intended.
- License selection, GitHub owner, and treatment of author metadata remain owner decisions; the design fixes technical identifiers and intentionally retains the existing cache path. The repository is not yet audited comprehensively, renamed, licensed, or published by creating this proposal.

### Out of Scope

New explanation features, provider integrations, productization, support guarantees, a release cadence, humour injected into generated explanations, and unapproved publication or destructive history cleanup.
