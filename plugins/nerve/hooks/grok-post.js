#!/usr/bin/env node
/**
 * Grok command hook: stdin event JSON → POST http://127.0.0.1:17890/v1/hook?producer=grok
 *
 * Grok's `type: http` runner refuses loopback and non-HTTPS URLs (SSRF guard),
 * so the official HTTP hook type cannot reach the hub. Always exit 0.
 */
"use strict";

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const INGEST_HOST = "127.0.0.1";
const INGEST_PORT = 17890;
const INGEST_TIMEOUT_MS = 1500;

function note(message) {
  try {
    const dir = path.join(os.homedir(), "Library/Logs/Nerve");
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, "nerve-hook.log"), `${new Date().toISOString()} grok ${message}\n`);
  } catch (_) {
    /* fail-open */
  }
}

function finish() {
  process.exit(0);
}

const chunks = [];
process.stdin.on("data", (chunk) => {
  chunks.push(chunk);
});
process.stdin.on("error", finish);
process.stdin.on("end", () => {
  const body = Buffer.concat(chunks);
  if (!body.length) {
    note("empty stdin");
    finish();
    return;
  }
  let request;
  try {
    request = http.request(
      {
        host: INGEST_HOST,
        port: INGEST_PORT,
        method: "POST",
        path: "/v1/hook?producer=grok",
        headers: {
          "User-Agent": "nerve-hook-grok/0.1",
          "Content-Type": "application/json",
          "Content-Length": body.length,
          Connection: "close",
        },
      },
      (response) => {
        note(`POST ${response.statusCode}`);
        response.resume();
        response.on("end", finish);
        response.on("error", finish);
      },
    );
  } catch (error) {
    note(`request ${error}`);
    finish();
    return;
  }
  request.setTimeout(INGEST_TIMEOUT_MS, () => {
    note("timeout");
    request.destroy();
    finish();
  });
  request.on("error", (error) => {
    note(`error ${error && error.message ? error.message : error}`);
    finish();
  });
  request.on("close", finish);
  request.end(body);
});
