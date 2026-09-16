/**
 * Ask notify helpers — mirrored gate used by macOS banners and VS Code toasts.
 */

import { strict as assert } from "node:assert";
import { parseJob, type Job } from "../../src/model/job";
import {
  askCopy,
  isAskElevated,
  isAskReason,
  shouldNotifyAsk,
} from "../../src/model/status";

function job(value: Record<string, unknown>): Job {
  const parsed = parseJob({ id: "a", name: "nerve", ...value });
  if (!parsed) throw new Error("parseJob rejected a test fixture");
  return parsed;
}

suite("ask notify gate", () => {
  test("review is an ask reason", () => {
    assert.equal(isAskReason("review"), true);
    assert.equal(isAskReason("resource"), false);
  });

  test("wait at suggested is not ask-elevated", () => {
    assert.equal(
      isAskElevated(
        job({
          attention: { level: "suggested", reason: "resource" },
        }),
      ),
      false,
    );
  });

  test("input at suggested is ask-elevated", () => {
    assert.equal(
      isAskElevated(
        job({
          attention: { level: "suggested", reason: "input" },
        }),
      ),
      true,
    );
  });

  test("first sight of an ask fires", () => {
    const next = job({
      attention: { level: "suggested", reason: "input" },
    });
    assert.equal(shouldNotifyAsk(undefined, next), true);
  });

  test("same-level ask heartbeat stays quiet", () => {
    const prev = job({
      attention: { level: "suggested", reason: "input" },
    });
    const next = job({
      attention: { level: "suggested", reason: "input", title: "still" },
    });
    assert.equal(shouldNotifyAsk(prev, next), false);
  });

  test("escalation from suggested to required fires", () => {
    const prev = job({
      attention: { level: "suggested", reason: "input" },
    });
    const next = job({
      attention: { level: "required", reason: "approval" },
    });
    assert.equal(shouldNotifyAsk(prev, next), true);
  });

  test("wait becoming ask fires", () => {
    const prev = job({
      attention: { level: "suggested", reason: "queue" },
    });
    const next = job({
      attention: { level: "suggested", reason: "decision" },
    });
    assert.equal(shouldNotifyAsk(prev, next), true);
  });

  test("ask copy stays gentle for review", () => {
    const copy = askCopy(
      job({
        name: "docs",
        attention: { level: "suggested", reason: "review" },
      }),
    );
    assert.match(copy.title, /review/i);
    assert.match(copy.body, /when you are ready/i);
  });
});
