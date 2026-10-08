## ADDED Requirements

### Requirement: Cross-session code result reuse

Completed code-file and visual-selection explanations SHALL support cross-session reuse for exact source, resolved mode, normalized target, supplied context and generation matches, including unsaved/unnamed inputs. Code-file and diff-file identities SHALL remain distinct; selection SHALL remain code. Keys SHALL preserve selection text and byte/virtual spans, excluding transient editor IDs. Restored notes SHALL bind only after validation and freshness checks.

#### Scenario: Same named file in another process
- **WHEN** a completed code-file request is repeated after restarting Neovim with identical content and generation settings
- **THEN** a valid retained result is installed without invoking the external agent, even if buffer numbers differ

#### Scenario: Shared buffer in code and diff windows
- **WHEN** an ordinary source window and a Diffview source window show the same working buffer and the user invokes Explainr file in each
- **THEN** source-window ownership resolves code-file and diff-file requests before cache lookup, and their entries remain distinct
- **AND** invocation from an associated reader uses its followed source rather than the reader's Markdown or the other window's cached mode

#### Scenario: Selection from a Diffview source
- **WHEN** Explainr selection or explain("selection", descriptor) is invoked from a Diffview source
- **THEN** lookup uses the exact selected-code target and supplied code context, not diff-file or hunk identity
- **AND** an equivalent ordinary-source selection can reuse that result only when source namespace, normalized target, supplied context and generation settings all match

#### Scenario: Unnamed or unsaved input
- **WHEN** an unnamed or unsaved buffer recreates the same normalized source, text and target in the same source namespace
- **THEN** matching retained notes can be reused without requiring a disk save or matching runtime buffer number
- **AND** structured source references bind to the current buffer without rewriting arbitrary explanation prose

#### Scenario: Same lines with different columns
- **WHEN** two selections span the same line numbers but select different text, byte columns or virtual spans
- **THEN** they do not share a cached answer merely because their line anchors match

#### Scenario: Equivalent reversed selection
- **WHEN** opposite endpoint directions select exactly the same text and normalized per-line spans
- **THEN** endpoint direction alone does not prevent reuse
- **AND** blockwise, exclusive, tab and multibyte boundaries retain their actual selected-region semantics

#### Scenario: Surrounding context changes
- **WHEN** selected text is unchanged but another supplied part of the current buffer changes
- **THEN** the old selection answer is not reused because its supplied context differs

#### Scenario: Source changes during cache lookup
- **WHEN** a matching entry is read but the source changes or the request is cancelled before installation
- **THEN** the late hit cannot install notes against the changed or superseded target
