import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { strict as assert } from "node:assert";

function extensionManifestPath(): string {
  let dir = __dirname;
  while (dir !== dirname(dir)) {
    const candidate = join(dir, "package.json");
    if (existsSync(candidate) && dir.endsWith("vsc-ext")) return candidate;
    dir = dirname(dir);
  }
  throw new Error(`could not locate vsc-ext/package.json from ${__dirname}`);
}

const pkg = JSON.parse(readFileSync(extensionManifestPath(), "utf8")) as {
  activationEvents?: string[];
  contributes?: {
    commands?: Array<{ command: string; title: string }>;
    viewsContainers?: { activitybar?: Array<{ id: string }> };
    configuration?: { properties?: Record<string, { default?: unknown }> };
  };
};

suite("manifest", () => {
  test("activates on startup so the status bar is ambient", () => {
    assert.ok(pkg.activationEvents?.includes("onStartupFinished"));
  });

  test("contributes an activity bar container", () => {
    assert.equal(pkg.contributes?.viewsContainers?.activitybar?.[0]?.id, "nerve");
  });

  test("never contributes reverse-control commands", () => {
    const commands = (pkg.contributes?.commands ?? []).map((item) =>
      item.command.toLowerCase(),
    );
    for (const forbidden of ["approve", "cancel", "submit", "reject", "dismiss"]) {
      assert.equal(
        commands.some((command) => command.includes(forbidden)),
        false,
        forbidden,
      );
    }
  });

  test("does not expose a hub endpoint setting", () => {
    const keys = Object.keys(pkg.contributes?.configuration?.properties ?? {});
    assert.equal(
      keys.some((key) => /endpoint|port|url/i.test(key)),
      false,
    );
  });
});
