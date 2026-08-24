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
