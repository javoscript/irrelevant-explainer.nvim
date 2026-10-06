# Spec Delta

## Purpose

Let users understand source code at a chosen scope using explanations grounded in the actual buffer contents, including unsaved changes.

## ADDED Requirements

### Requirement: File and visual scopes

The plugin SHALL offer whole-file and visual-selection explanation in ordinary text buffers without requiring a syntax parser. It SHALL preserve the selected text boundaries and reject an empty selection without invoking AI.

#### Scenario: Explain an unsaved file
- **WHEN** the user requests a file explanation after editing the buffer without saving
- **THEN** the explanation target contains all current buffer text rather than the on-disk version

#### Scenario: Explain a characterwise selection
- **WHEN** the user selects a portion of a line through a portion of another line
- **THEN** the target preserves those character boundaries and records their original source line positions

#### Scenario: Explain linewise or blockwise selections
- **WHEN** the user requests explanation of a linewise selection or a rectangular blockwise selection
- **THEN** the target contains the selected complete lines or selected per-line column spans, respectively, with their original source positions

#### Scenario: Empty selection
- **WHEN** the requested selection contains no text
- **THEN** the plugin reports that there is no selected code and does not start the external command

### Requirement: Structural scopes

The plugin SHALL resolve the smallest enclosing function or class at the cursor using Tree-sitter and supported language queries. Missing parsers, queries, or enclosing structures SHALL produce an actionable message instead of silently explaining a different scope.

#### Scenario: Nested function
- **WHEN** the cursor is inside a function nested within another function and function scope is requested
- **THEN** the inner function is the explanation target

#### Scenario: Class scope
- **WHEN** the cursor is inside a method of a class in a supported language and class scope is requested
- **THEN** the enclosing class, not only the method, is the explanation target

#### Scenario: Structural scope unavailable
- **WHEN** function or class scope cannot be resolved because the parser, query, or enclosing structure is unavailable
- **THEN** the plugin explains the limitation and offers file or visual scope without automatically sending a broader target

### Requirement: Target and context separation

The request SHALL distinguish the code to annotate from contextual code. In code mode the current file SHALL provide context for a narrower target, while notes SHALL anchor only to lines intersecting that target.

#### Scenario: Function depends on an import
- **WHEN** a selected function calls a helper imported outside its range
- **THEN** the request includes the current file as context, identifies the function as the target, and permits notes only inside that function

### Requirement: Behavior-focused notes

Code explanation requests SHALL ask for concise behavior-focused notes and full detail, including visible assumptions and limitations. They SHALL prohibit presenting inferred behavior of unavailable dependencies as an established fact.

#### Scenario: External API behavior unavailable
- **WHEN** the target calls an API whose implementation is absent from the supplied context
- **THEN** the prompt asks the agent to distinguish visible call behavior from unknown error handling or side effects

### Requirement: Snapshot-bound results

An explanation SHALL remain bound to the source snapshot used to request it. An edit or target change before completion SHALL invalidate the pending result; edits after display SHALL mark existing explanations stale and remove active alignment until explicitly refreshed.

#### Scenario: Edit while waiting
- **WHEN** the source changes after a request starts and before it completes
- **THEN** the old result is not displayed against the edited code

#### Scenario: Edit after display
- **WHEN** the user changes code with an explanation already open
- **THEN** the pane identifies the explanation as stale, stops displaying it as current line-aligned guidance, and does not automatically start a new AI request
