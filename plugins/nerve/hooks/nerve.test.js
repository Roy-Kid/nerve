"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { mapEvent, eventName, sessionId } = require("./nerve.js");

test("SessionStart is Ready, not Running", () => {
  const f = mapEvent("sessionstart", { hook_event_name: "SessionStart" });
  assert.equal(f.current.type, "starting");
  assert.equal(f.attention.level, "none");
});

test("Stop without background is your turn", () => {
  const f = mapEvent("stop", { hookEventName: "Stop" });
  assert.equal(f.current.type, "idle");
  assert.equal(f.attention.reason, "input");
  assert.equal(f.attention.title, "Your turn in agent");
});

test("Stop with shell background is Running", () => {
  const f = mapEvent("stop", {
    hook_event_name: "Stop",
    background_tasks: [{ type: "shell", description: "npm test" }],
  });
  assert.equal(f.current.type, "subagent");
  assert.equal(f.attention.level, "none");
});

test("PreCompact with shell background stays Running", () => {
  const f = mapEvent("precompact", {
    hook_event_name: "PreCompact",
    background_tasks: [{ type: "shell", description: "npm test" }],
  });
  assert.equal(f.current.type, "subagent");
  assert.equal(f.attention.level, "none");
});

test("PreCompact without background is thinking", () => {
  const f = mapEvent("precompact", { hook_event_name: "PreCompact" });
  assert.equal(f.current.type, "thinking");
  assert.equal(f.current.summary, "Compacting context");
  assert.equal(f.attention.level, "none");
});

test("PostCompact without background is your turn", () => {
  const f = mapEvent("postcompact", { hook_event_name: "PostCompact" });
  assert.equal(f.current.type, "idle");
  assert.equal(f.attention.reason, "input");
});

test("PostCompact with monitor stays monitor", () => {
  const f = mapEvent("postcompact", {
    hook_event_name: "PostCompact",
    background_tasks: [{ type: "monitor" }],
  });
  assert.equal(f.current.type, "monitor");
  assert.equal(f.outcome, "partial");
});

test("event name strips punctuation", () => {
  assert.equal(eventName({ hook_event_name: "User_Prompt-Submit" }), "userpromptsubmit");
});

test("session id prefers session_id", () => {
  assert.equal(sessionId({ session_id: "abc" }), "abc");
});

// ── Wire paths ──────────────────────────────────────────────────────────────

const { fileUri, pathStyle, buildLocation } = require("./nerve.js");

test("a posix cwd encodes exactly as it always did", () => {
  assert.equal(fileUri("/Users/me/proj"), "file:///Users/me/proj");
  assert.equal(fileUri("/Users/me/proj foo"), "file:///Users/me/proj%20foo");
});

test("a windows cwd gains the RFC slash and keeps its colon", () => {
  assert.equal(fileUri("C:\\Users\\me\\work"), "file:///C:/Users/me/work");
  assert.equal(fileUri("c:/Users/me/work"), "file:///c:/Users/me/work");
});

test("a unc server becomes the url authority", () => {
  assert.equal(fileUri("\\\\srv\\share\\proj"), "file://srv/share/proj");
});

test("a relative cwd gets no url", () => {
  // `C:work` is relative to the current directory on drive C.
  for (const cwd of ["proj", "~/proj", "C:work", "", null]) {
    assert.equal(fileUri(cwd), null, String(cwd));
  }
});

test("path style knows both OSes", () => {
  assert.equal(pathStyle("/tmp"), "posix");
  assert.equal(pathStyle("C:\\tmp"), "windows");
  assert.equal(pathStyle("\\\\srv\\share"), "windows");
  assert.equal(pathStyle("tmp"), null);
});

test("an ide deep link carries a drive after the url's slash", () => {
  const prev = process.env.VSCODE_PID;
  process.env.VSCODE_PID = "1";
  try {
    assert.equal(
      buildLocation({}, "C:\\work\\nerve").openURL,
      "vscode://file/C:/work/nerve",
    );
    assert.equal(
      buildLocation({}, "/Users/me/nerve").openURL,
      "vscode://file/Users/me/nerve",
    );
  } finally {
    if (prev === undefined) delete process.env.VSCODE_PID;
    else process.env.VSCODE_PID = prev;
  }
});

test("a windows cwd still reports a focus hint with the path in it", () => {
  const loc = buildLocation({}, "C:\\work\\nerve");
  assert.ok(loc.focusHint.endsWith(" · C:\\work\\nerve"));
});
