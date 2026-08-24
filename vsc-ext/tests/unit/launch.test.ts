import { strict as assert } from "node:assert";
import { HubLauncher, SPAWN_THROTTLE_MS } from "../../src/hub/launch";

suite("hub launch", () => {
  test("already serving never spawns", async () => {
    let spawned = 0;
    const launcher = new HubLauncher(
      {
        spawn: () => {
          spawned += 1;
        },
      },
      { now: () => 0 },
      { isServing: () => true },
    );
    assert.equal(await launcher.ensure("/bin/nerve-hub", true), "alreadyServing");
    assert.equal(spawned, 0);
  });

  test("missing binary is missing", async () => {
    const launcher = new HubLauncher(
      { spawn: () => undefined },
      { now: () => 0 },
      { isServing: () => false },
    );
    assert.equal(await launcher.ensure(undefined, true), "missing");
  });

  test("disabled spawn does not fire", async () => {
    let spawned = 0;
    const launcher = new HubLauncher(
      {
        spawn: () => {
          spawned += 1;
        },
      },
      { now: () => 0 },
      { isServing: () => false },
    );
    assert.equal(await launcher.ensure("/bin/nerve-hub", false), "disabled");
    assert.equal(spawned, 0);
  });

  test("throttle suppresses a second spawn", async () => {
    let now = 0;
    let spawned = 0;
    const launcher = new HubLauncher(
      {
        spawn: () => {
          spawned += 1;
        },
      },
      { now: () => now },
      { isServing: () => false },
    );
    assert.equal(await launcher.ensure("/bin/nerve-hub", true), "spawned");
    assert.equal(await launcher.ensure("/bin/nerve-hub", true), "throttled");
    now = SPAWN_THROTTLE_MS;
    assert.equal(await launcher.ensure("/bin/nerve-hub", true), "spawned");
    assert.equal(spawned, 2);
  });

  test("a refused spawn is failed", async () => {
    const launcher = new HubLauncher(
      {
        spawn: () => {
          throw new Error("nope");
        },
      },
      { now: () => 0 },
      { isServing: () => false },
    );
    assert.equal(await launcher.ensure("/bin/nerve-hub", true), "failed");
  });
});
