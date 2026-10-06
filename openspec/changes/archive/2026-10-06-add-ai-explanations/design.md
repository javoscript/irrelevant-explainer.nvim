# Design

## Context

See [proposal.md](proposal.md) for motivation and scope. This repository currently contains only OpenSpec/tooling configuration: there is no plugin, test harness, or established Lua module convention to preserve. The design is needed because source display geometry, review-wide context, and external command protocols cross several boundaries.

Relevant investigated integration contracts:

- Diffview documents `diff_buf_win_enter`, view lifecycle/layout hooks, and `actions.view_windo` for discovering displayed role/window/buffer IDs. Its selected entry and comparison revision metadata require private access. Buffer hooks fire separately during asynchronous file loading, not as an atomic whole-comparison event.
- Ordinary Diffview roles are `a` (old) and `b` (new); merge layouts have different semantics. A shared null buffer can represent absent or binary versions and cannot by itself identify a deleted file.
- Gitsigns full blame achieves row correspondence using a one-row-per-line buffer and changes source wrapping, folds, and native scroll binding. That strategy cannot be copied unchanged into a folded/wrapped diff with longer explanation detail.
- OpenCode `run --format json` accepts prompt text from non-TTY stdin and emits completed text parts at `event.part.text`; process completion is significant. Codex `exec - --json` accepts stdin and exposes completion/failure events. Neither transport's first assistant message is necessarily its final answer.

These are inspected upstream contracts, not evidence that this plugin has run successfully. Supported external-tool and Diffview versions must be recorded and checked during implementation.

## Goals / Non-Goals

**Goals:**

- Make immutable snapshots and explicit anchors the shared contract between collection, prompting, execution, and rendering.
- Resolve viewport alignment independently of AI so deterministic fixtures can prove geometry first.
- Let context explain the whole review while keeping output bounded to the focused target.
- Keep agent-specific protocols and private Diffview access out of the core explanation/rendering logic.

**Non-Goals:**

- A general chat or coding-agent client, persistent conversational sessions, automatic code edits, or autonomous repository investigation.
- Native OAuth, credential storage, subscription enforcement, MR-hosting APIs, or fetching remote review branches.
- All possible diff layouts, arbitrary binary explanations, automatic parser installation, or a narrative/inline renderer in this first change.
- Automatic summarization of oversized reviews or an assertion that schema-valid AI explanations are factually correct.

## Decisions

### 1. A small Lua plugin with separate collection, execution, and presentation responsibilities

Use Neovim 0.11+ as the proposed initial compatibility baseline, with its asynchronous process and Tree-sitter/window APIs. Provide lazy, user-invoked commands and `require("explainr").setup(...)`; do not require Diffview for ordinary code mode. Start with a minimal headless Lua test harness and deterministic fake command fixtures, not a running provider account.

Keep public setup/commands in the plugin entrypoint, source and review collection separate from prompt construction, external-command execution separate from output validation, and viewport projection separate from session lifecycle. Create modules only when these responsibilities need a boundary; do not build a provider SDK, generic event bus, or class hierarchy.

**Alternative:** delegate collection as well as reasoning to the external agent. Rejected because it could inspect different saved files/revisions, ignore unsaved text, execute tools, and return anchors unrelated to the displayed snapshot.

### 2. Define target, context, and generation identity separately

A request snapshot records mode, source identities, exact target spans, contextual text, and a content fingerprint. Code mode uses current buffer contents, including an identity for unnamed buffers. The entire current file supplies context for narrower scopes; characterwise/blockwise selections retain per-line columns even though annotations are line-anchored. Structural queries select the smallest enclosing matching node without silently falling back to another scope.

Ship tested structural queries for Lua functions and Python/JavaScript/TypeScript functions and classes, using installed parsers. Other language/parser/query combinations report structural scope unavailability; file and visual modes continue to work. The grammar fixtures and compatibility documentation define the initial supported set rather than pretending all parsers share function/class node types.

For diff mode, record explicit old/new Git or working/index identities, selected comparison entries, file status, old/new paths, presence/binary markers, before/after text, patches, and the focused file or hunk. Never infer versions from left/right screen position or from an empty/null buffer. All changed-file patches are context, while only the focused target is eligible for notes.

Maintain a generation identity per explanation session. Target switches cancel or invalidate pending results; source/review content changes also invalidate the snapshot fingerprint. Before installing a result, recheck the generation and content identities. Mark already displayed results stale and remove active notes after edits rather than attempting to shift AI claims onto modified code.

**Alternative:** let extmarks track notes through edits. Rejected for explanation validity: moving a mark does not prove the explanation still describes the edited behavior.

### 3. Assemble the entire review before building the prompt

The Diffview adapter obtains the exact comparison and complete file list. Use Git version data for committed/index sides and current text for participating working-buffer sides. Overlay unsaved buffers before generating patches; never pair a saved-file patch with different displayed text. New and deleted versions are explicit absences. Preserve rename identity, including renames without textual changes. Binary entries remain in the manifest with an explicit reason they have no line-explainable text.

A Diffview view can expose staged and working comparisons with different endpoints. Treat the selected entry's coherent revision pair as the review scope, clearly label it, and include every entry in that comparison. Do not silently combine index-to-working patches with HEAD-to-index patches or filter the review to just the visible file. Reject a view/scope that cannot be resolved to a supported pair.

Include all textual patches, the focused file's complete available versions, and complete versions of changed documentation/decision files. Initially recognize Markdown, reStructuredText, and plain-text documentation by extension, plus conventional documentation directories; OpenSpec Markdown naturally participates without a special business-rule extractor. Keep other changed textual files in the patch context. The manifest says which full documents were included. No unmodified repository file is automatically explored or attached.

Read mutable inputs consistently: check participating buffers and filesystem/index/revision identities before and after collection, and reject an incoherent snapshot. Revalidate mutable comparison inputs before accepting an agent result, even if the changed file is not currently visible. Listen for relevant buffer edits and Diffview refreshes, and invalidate the review cache accordingly.

The prompt has distinct instructions, comparison identity/manifest, labeled versioned context, focused target, and an output contract. Repository text is untrusted data. Diff instructions emphasize observable behavior changes, documented requirements, tests as evidence of expectations (not proof tests passed), inferred/unknown intent, and visible contradictions. Ask for useful sparse notes, not a paraphrase of every line.

**Alternative:** provide only the focused patch or ask the agent to find relevant documents. Rejected because it omits cross-file decisions and cannot guarantee whole-comparison context. Automatic review summarization is also excluded: it would weaken the chosen complete-context contract.

### 4. Use one validated note contract across both modes

The final explanation is a single JSON object with `version: 1` and a `notes` array. Each note has:

- `summary`: nonempty, single-line concise text.
- `detail`: nonempty full explanation available without a second request.
- `anchors`: one or more `{ path, side, start_line, end_line }` ranges, with 1-based inclusive line numbers. Code notes use one `buffer` range; diff notes use `old`, `new`, or one of each for a replacement.
- `intent_basis`: `documented`, `inferred`, or `unknown`.
- `evidence`: zero or more ranges using the same path/side/line convention, drawn from the supplied context. Documented-intent notes require evidence.

For renamed files, anchors/evidence use each side's actual path, not a guessed common name. Empty/absent versions have no valid line anchors. A legitimately empty notes array is permitted; it is different from a missing answer or failed execution.

Validate required fields, supported version/sides, integer range bounds, focused target membership, and evidence availability. Reject malformed output as a whole with a useful message rather than guessing nearby valid lines or stripping arbitrary prose to find a JSON fragment. Schema enforcement, where supported by the command, supplements this validation but does not replace it. Validation can establish that cited context exists, not that the model's interpretation is true.

For nonfocused files supplied only as patches, retain the transmitted old/new line spans. A citation must be entirely present in those spans; knowing a file's full length or having collected its contents internally does not make an unsent range valid evidence. In code mode, an anchor range must fit the selected target's line extent, with the selected character/column spans retained separately in the prompt.

**Alternative:** align free-form Markdown or demand one model paragraph per source line. Rejected because both are fragile and neither reliably represents deletions, sparse notes, or cross-file evidence.

### 5. External commands are a transport, not provider integrations

Proposed configuration shape:

```lua
require("explainr").setup({
  ai = {
    command = {
      "opencode", "run",
      "--model", "provider/model",
      "--agent", "explain", -- user-created, restricted agent
      "--format", "json",
    },
    output = "opencode", -- also "codex", "plain", or a decoder function
    timeout_ms = 300000,
  },
  context = {
    max_bytes = 262144,
  },
})
```

These names/defaults are proposed implementation decisions, not a currently available API. The executable, agent, and model must already be configured by the user. Launch the argument list directly with the project directory as cwd, inherit the user's tool environment, write the full prompt to stdin, then close stdin. Do not append the prompt to a shell command, initiate interactive login, add auto-approval flags, or select another provider on failure. A user-managed script can adapt tools without stdin support to this same transport.

Initial result handling can accumulate stdout/stderr separately until exit; token-by-token note rendering is unnecessary and would expose unvalidated partial output. OpenCode decoding groups completed `text` events by message ID and uses the final assistant message after successful local process completion. Codex decoding uses final completed assistant content with successful turn completion; failure events override partial text. Plain mode expects only the final JSON object. A custom decoder receives captured stdout, stderr, and exit status and returns final explanation text or an error, which still passes through common validation.

Timeout/cancellation terminates owned local execution and invalidates its generation before any late output can arrive. For tools that attach to a persistent server, client termination might not stop remote generation or billing; document this limitation and require tool-specific cancellation before claiming stronger support. Fresh standalone invocations are the default, with no implicit `--continue`, session reuse, sharing, or server attachment.

The command controls provider billing and may persist supplied code in its own history. Recommend a dedicated agent that denies edits, shell/MCP actions, delegation, and interactive questions when only supplied-context inference is required. A read-only filesystem sandbox alone does not prohibit all remote-tool side effects. Arbitrary user commands are trusted configuration, not sandboxed by Explainr.

**Alternative:** implement direct provider authentication and billing adapters. Rejected for v1 because configured tools already own them and the user explicitly prefers delegation.

### 6. Budget the complete serialized prompt without pretending to know provider tokens

Use a configurable UTF-8 byte budget (`context.max_bytes`) checked after assembly of instructions, context, target, and output contract. Report the actual byte count and limit, and state that provider token consumption is unknown; bytes are a guardrail, not a universal context-window estimate. The proposed default is 256 KiB and can be raised for the user's tool/model.

On overflow or missing required textual content, do not launch the agent. Offer increasing the budget, choosing a smaller explicit comparison, or fixing collection errors. Do not silently strip documents, drop files, truncate the prompt, or ask for a summary as if it preserved the whole review. Provider context errors can still happen below the byte limit and must be surfaced.

Cache assembled review snapshots and validated results in memory by content fingerprint and target. Reusing collection does not guarantee provider prompt caching or reduced billing; independent focused-file requests may resend the same review context. Do not persist code snapshots in a new plugin cache by default.

### 7. Render a projection of source display rows, not a padded essay

Option A is the only renderer in scope. Use a read-only scratch window to the right, with `diff`, `scrollbind`, `cursorbind`, and wrapping disabled in that window only. Keep source options intact. Equal source/note file line numbers and native `scrollbind` are insufficient because wraps, folds, and diff filler have different physical heights.

Build a viewport projection mapping source display rows to source ranges and note IDs. Use supported window geometry/view APIs to account for `topline`, partially scrolled wrapped lines, folds, diff filler, and relevant decoration rows. Paint one annotation-buffer row per source display row; blank rows preserve height. Long summaries are display-width truncated with an expansion indicator. Use matched content-area heights, including compatible winbar placement, so header geometry does not shift notes.

Show an anchor's summary at the first visible display row of its range; wrapped continuations remain blank. Closed folds collapse applicable notes into a clearly labeled folded-content row; multiple notes on the same projected row share an indicator and preserve their original anchors in detail. Diff deletion notes map from the old-side range to the corresponding comparison/filler rows in the followed window. Do not copy removed text into the new source or create synthetic source lines.

Source scrolling, resizing, wrapping/fold changes, and layout changes rebuild the projection. Explanation-pane scroll commands drive the paired source's view, then rebuild the projection; they do not independently scroll annotation prose. Guard synchronization against recursive events. Keep the viewport's annotation cursor stable during repaint and translate note movement back to its source range. In a diff view, let original source panes retain their own existing synchronization.

`Enter` on a note opens existing detail in a temporary floating window; `Esc` closes it. Detail includes source anchors, intent labels, and evidence. Opening detail does not rebuild context, invoke AI, or insert rows. Status belongs in matched headers/status areas, not extra annotation rows; stale/failure states clear active notes.

**Alternative:** borrow Gitsigns' padded full-file buffer and disable source wraps/folds. Rejected because it changes reading behavior and breaks Diffview alignment. Option B would simplify long prose but was not the chosen interaction.

### 8. Isolate Diffview compatibility and make lifecycle explicit

Use public view/buffer/layout events where possible without replacing user hooks. Coalesce per-side events, discover live role/window/buffer IDs via the documented action, and inspect comparison metadata only after the displayed pair is coherent. Put unavoidable private `get_current_view`/selected-entry/revision access in one adapter and test it against a recorded supported Diffview revision. Do not insert the explanation window into Diffview's private layout objects.

At activation, follow the relevant source role and snapshot comparison state. On file/layout switches, reacquire live windows instead of assuming cached IDs survive. A session owns only its scratch window/buffer, detail window, event handlers, cached snapshot/result, and pending execution. Explicit disable/source closure cancels and removes those resources; normal file switches reset the target and require an explicit explanation request unless a matching valid result is already cached.

Proposed commands are `:ExplainrCode file|function|class|selection`, `:ExplainrDiff file|hunk`, `:ExplainrRefresh`, `:ExplainrCancel`, and `:ExplainrClose`. Setup installs no global editing mappings; detail/scroll mappings are local to the explanation UI. Document selection invocation so marks/mode are captured before command-line transitions lose the intended shape.

**Alternative:** couple the core renderer to Diffview private layout objects or treat every buffer-enter event as a ready comparison. Rejected because asynchronous transitions can expose mixed file versions and private layouts can be reconstructed.

## Risks / Trade-offs

- Exact screen-row projection is the highest UI risk -> implement and inspect fixed-note fixtures first, including top/bottom boundaries, wraps, folds, unequal old/new line counts, and deletion-only hunks; do not weaken alignment to satisfy an easy test.
- Private Diffview metadata and CLI event formats can change -> keep narrow adapters/decoders, record tested versions, and fail clearly on unsupported shapes.
- Whole-review prompts can be large and repeated per target -> explicit budgets, reusable local collection/results, and honest provider-limit errors; no silent loss of business context.
- Mutable working/index content can race collection or inference -> content identities before/after snapshot creation and again before installation, including nonfocused changed files.
- Models can hallucinate rationale despite valid references -> expose evidence and intent labels, make contradictions part of the prompt, and never equate schema validation with semantic correctness.
- User-supplied agents can access tools or persist sensitive code -> document the trust boundary and provide restricted configuration examples without claiming to enforce arbitrary-command safety.
- Renderer state can outlive replaced windows -> ownership-based cleanup, generation guards, and lifecycle integration tests.

## Migration Plan

There is no existing implementation or public API to migrate. Deliver the plugin incrementally using fixed notes before real inference, then add code scopes, process execution, and complete-review Diffview collection. Verification uses deterministic headless/process fixtures and inspected rendered captures; a real authenticated tool smoke test is optional and must not be required for the offline test suite.

No package publication, push, or release is authorized by this proposal. Users opt in by configuring and invoking the plugin. Rollback is disabling/removing it; it must not leave source text, repository files, or source window options modified. The external agent's own retained history remains outside that rollback boundary.

## References

- [Diffview hooks and actions](https://github.com/sindrets/diffview.nvim/blob/main/doc/diffview.txt)
- [Diffview view/selected-entry implementation](https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/scene/views/diff/diff_view.lua)
- [Gitsigns full blame implementation](https://github.com/lewis6991/gitsigns.nvim/blob/main/lua/gitsigns/actions/blame.lua)
- [OpenCode CLI](https://opencode.ai/docs/cli/) and [run implementation](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/cli/cmd/run.ts)
- [OpenCode agent permissions](https://opencode.ai/docs/agents/)
- [Codex noninteractive execution](https://learn.chatgpt.com/docs/non-interactive-mode)
