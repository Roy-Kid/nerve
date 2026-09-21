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

test("Stop while the gate is retrying stays running", () => {
  const f = mapEvent("stop", { hook_event_name: "Stop", stopHookActive: true });
  assert.equal(f.current.type, "thinking");
  assert.equal(f.attention.level, "none");
});

test("session-end observe Stop does not paint your turn", () => {
  assert.equal(mapEvent("stop", { hook_event_name: "Stop", reason: "channel_closed" }), null);
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

// ── Transport ───────────────────────────────────────────────────────────────

const http = require("node:http");
const { postSnapshot } = require("./nerve.js");

/** A throwaway ingest server on an ephemeral port. Never 17890. */
function ingest(handler) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => { body += chunk; });
      req.on("end", () => {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end("{}");
        handler({ method: req.method, url: req.url, headers: req.headers, body });
      });
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("a snapshot arrives as a well-formed POST", async () => {
  let seen;
  const server = await ingest((request) => { seen = request; });
  const { port } = server.address();
  assert.notEqual(port, 17890, "a test must never take the hub's own port");

  try {
    await postSnapshot("thinkpad", "windows", { id: "j", name: "nerve" }, port);
  } finally {
    // The handler runs before the response is fully flushed to us; give the
    // event loop the turn it needs before tearing the server down.
    await new Promise((r) => setImmediate(r));
    server.close();
  }

  assert.equal(seen.method, "POST");
  assert.equal(seen.url, "/v1/snapshot");
  assert.equal(seen.headers["content-type"], "application/json");
  const payload = JSON.parse(seen.body);
  assert.equal(payload.alias, "thinkpad");
  assert.equal(payload.machineKind, "windows");
  assert.deepEqual(payload.jobs, [{ id: "j", name: "nerve" }]);
});

test("a multibyte job name keeps its Content-Length honest", async () => {
  // The hand-written request used `body.length` on a Buffer, which is bytes —
  // correct, but only by luck of the author remembering. Pin it.
  let seen;
  const server = await ingest((request) => { seen = request; });
  const { port } = server.address();
  try {
    await postSnapshot("mac", "darwin", { id: "j", name: "项目" }, port);
  } finally {
    await new Promise((r) => setImmediate(r));
    server.close();
  }
  const expected = Buffer.byteLength(seen.body);
  assert.equal(Number(seen.headers["content-length"]), expected);
  assert.equal(JSON.parse(seen.body).jobs[0].name, "项目");
});

test("nothing listening resolves rather than throwing", async () => {
  // Fail-open: no hook event may ever block or crash an agent.
  const server = await ingest(() => {});
  const { port } = server.address();
  server.close();
  await new Promise((r) => server.on("close", r));

  await postSnapshot("mac", "darwin", { id: "j", name: "nerve" }, port);
});

test("Grok hooks are command posts, not type:http to loopback", () => {
  // Grok's HTTP runner blocks 127.0.0.1 (SSRF) and non-HTTPS URLs, so a
  // type:http hook never reaches the hub.
  const grok = require("./grok.json");
  const events = Object.keys(grok.hooks);
  assert.ok(events.includes("PreToolUse"));
  assert.ok(events.includes("SessionStart"));
  for (const event of events) {
    for (const group of grok.hooks[event]) {
      for (const hook of group.hooks) {
        assert.equal(hook.type, "command", event);
        assert.match(hook.command, /grok-post\.js/);
        assert.equal(hook.timeout, 2);
      }
    }
  }
});

test("grok-post.js exits 0 with empty stdin", async () => {
  const { spawn } = require("child_process");
  const child = spawn(process.execPath, [require("path").join(__dirname, "grok-post.js")], {
    stdio: ["pipe", "ignore", "ignore"],
  });
  child.stdin.end();
  const code = await new Promise((resolve) => child.on("close", resolve));
  assert.equal(code, 0);
});
