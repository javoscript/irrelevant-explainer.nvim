#!/usr/bin/env python3
"""Offline transport fixture: never imports or launches a provider CLI."""
import json
import os
import signal
import sys
import time

mode = sys.argv[1]
prompt = sys.stdin.buffer.read()
answer = '{"version":1,"notes":[]}'
progress = '{"version":1,"notes":[],"progress":true}'

if mode.startswith("whole-review"):
    request = json.loads(prompt.decode().split("UNTRUSTED REVIEW REQUEST JSON:\n", 1)[1])
    response = {key: request[key] for key in ("phase", "request_id", "snapshot_id")}
    response["version"] = 3
    if request["phase"] == "annotate":
        response["units"] = [{"unit_id": unit["unit_id"], "notes": [], "findings": []}
                             for unit in request["units"]]
    elif request["phase"] == "reduce":
        response.update(child_ids=request["child_ids"], findings=[])
    else:
        assert request["phase"] == "synthesize"
        response.update(child_ids=request["child_ids"], review={
            "title": "Working-tree review", "sections": [{
                "heading": "Net changes since HEAD",
                "detail": "Distributed annotations connect the comparison's changes. This offline fixture tests the reader, not semantic correctness; intent remains unknown.",
                "intent_basis": "unknown", "evidence": [],
                "file_ids": [file["file_id"] for file in request["manifest"]],
            }],
        })
    answer = json.dumps(response)
    mode = mode.removeprefix("whole-review").lstrip("-") or "plain"
    if mode == "truncated":
        answer, mode = answer[:-8], "plain"


def event(value):
    return json.dumps(value, ensure_ascii=False) + "\n"


def text(message, part, value, completed=True):
    return {"type": "text", "part": {
        "type": "text", "messageID": message, "id": part, "text": value,
        "time": {"start": 1, **({"end": 2} if completed else {})},
    }}


if mode == "identity":
    sys.stderr.write("stderr only\r\n")
    sys.stdout.write(json.dumps({"stdin": prompt.decode(), "argv": sys.argv[2:], "cwd": os.getcwd()}))
elif mode == "plain":
    sys.stderr.write("diagnostic only\n")
    sys.stdout.write(answer)
elif mode in ("opencode", "opencode-error"):
    values = [
        text("progress", "p1", progress),
        {"type": "tool_use", "part": {"type": "tool", "text": progress}},
        {"type": "reasoning", "part": {"text": progress}},
        text("final", "f1", answer[:14]),
        text("progress", "p2", "older message finishes late"),
        text("final", "f2", answer[14:]),
    ]
    if mode.endswith("error"):
        values.append({"type": "error", "error": {"data": {"message": "usage limit"}}})
    wire = "".join(map(event, values)).encode()
    # An event split across writes, then several events in a coalesced write.
    for chunk in (wire[:9], wire[9:31], wire[31:]):
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        time.sleep(0.015)
elif mode in ("codex", "codex-error"):
    values = [
        {"type": "turn.started"},
        {"type": "item.completed", "item": {"type": "agent_message", "text": progress}},
        {"type": "item.updated", "item": {"type": "agent_message", "text": progress}},
        {"type": "item.completed", "item": {"type": "reasoning", "text": progress}},
        {"type": "item.completed", "item": {"type": "agent_message", "text": answer}},
        {"type": "turn.completed"},
    ]
    if mode.endswith("error"):
        values.append({"type": "turn.failed", "error": {"message": "authentication required"}})
    wire = "".join(map(event, values)).encode()
    for start in range(0, len(wire), 17):
        sys.stdout.buffer.write(wire[start:start + 17])
        sys.stdout.buffer.flush()
elif mode == "nonzero":
    sys.stdout.write(answer)
    sys.stderr.write("authentication required; no fallback\n")
    sys.exit(7)
elif mode == "empty":
    pass
elif mode == "interrupted":
    os.kill(os.getpid(), signal.SIGTERM)
elif mode == "slow":
    sys.stdout.write(progress)
    sys.stdout.flush()
    # SIGTERM resistance discriminates real stopping from just invalidation.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(0.4)
    sys.stdout.write(answer)
    sys.stdout.flush()
elif mode == "eof":
    sys.stdout.buffer.write(prompt)
elif mode in ("review", "review-overview"):
    context = json.loads(prompt.decode().split("UNTRUSTED SNAPSHOT JSON:\n", 1)[1].split("\nFOCUSED TARGET JSON:\n", 1)[0])
    files = {(f["path"], f["side"]): f["lines"] for f in context["files"]}
    assert files[("openspec/spec.md", "new")][1] == "Only owners may cancel."
    assert files[("docs/adr.md", "new")][0] == "Rationale: preserve the owner's decision."
    assert ("tests/policy.txt", "new") in files
    notes = [
        {"summary": "Editors still bypass owner-only cancellation.",
         "detail": "The new editor branch permits cancellation by nonowners, contradicting the supplied owner-only requirement. The changed tests expect editors to be rejected. The ADR's unchanged rationale explains why ownership matters. These fixture notes demonstrate evidence rendering; they are not an AI correctness claim.",
         "anchors": [{"path": "policy.lua", "side": side, "start_line": 4, "end_line": 4} for side in ("old", "new")],
         "intent_basis": "documented", "evidence": [
             {"path": "openspec/spec.md", "side": "new", "start_line": 2, "end_line": 2},
             {"path": "docs/adr.md", "side": "new", "start_line": 1, "end_line": 1}]},
        {"summary": "Remove the legacy fallback.", "detail": "The old fallback branch is removed without replacement. This note stays anchored to removed old-side code, even when the followed new pane shows filler.",
         "anchors": [{"path": "policy.lua", "side": "old", "start_line": 8, "end_line": 9}],
         "intent_basis": "unknown", "evidence": []},
    ]
    if mode == "review-overview":
        target = json.loads(prompt.decode().split("FOCUSED TARGET JSON:\n", 1)[1])
        assert target["scope"] == "file"
        assert "file overview as the FIRST note" in prompt.decode()
        notes.insert(0, {
            "kind": "overview",
            "summary": "File overview: controls cancellation; changes editor access.",
            "detail": "This file decides whether a user may cancel an owned operation. The diff replaces the admin bypass with an editor-role bypass and removes the legacy fallback. The resulting editor bypass still conflicts with the supplied owner-only requirement.",
            "anchors": target["anchors"],
            "intent_basis": "inferred", "evidence": [],
        })
    sys.stdout.write(json.dumps({"version": 1, "notes": notes}))
elif mode in ("explain", "explain-slow", "explain-invalid"):
    target = json.loads(prompt.decode().split("FOCUSED TARGET JSON:\n", 1)[1])
    if mode == "explain-slow":
        time.sleep(0.4)
    anchors = target["anchors"]
    selected = next((a for a in anchors if a["side"] == "new"), anchors[0] if anchors else None)
    notes = []
    if selected:
        for label, line in (("Fixture start", selected["start_line"]), ("Fixture end", selected["end_line"])):
            anchor = {**selected, "start_line": line, "end_line": line}
            if mode == "explain-invalid":
                anchor["end_line"] = 99999
            notes.append({"summary": label, "detail": "Full fixture explanation, already returned.",
                          "anchors": [anchor], "intent_basis": "unknown", "evidence": []})
    sys.stdout.write(json.dumps({"version": 1, "notes": notes}))
else:
    sys.stderr.write("unknown fixture mode\n")
    sys.exit(2)
