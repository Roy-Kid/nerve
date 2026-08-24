import { strict as assert } from "node:assert";
import { locateHub, type BinaryProbe } from "../../src/hub/locate";

function probe(hits: Record<string, boolean>, pathHit?: string): BinaryProbe {
  return {
    isExecutable(path: string) {
      return Boolean(hits[path]);
    },
    onPath() {
      return pathHit;
    },
  };
}

suite("hub locate", () => {
  test("prefers a checkout release binary", () => {
    const found = locateHub(
      probe({ "/repo/target/release/nerve-hub": true }),
      "/home/me",
      "/repo/vsc-ext",
    );
    assert.equal(found, "/repo/target/release/nerve-hub");
  });

  test("homebrew beats cargo", () => {
    const found = locateHub(
      probe({
        "/opt/homebrew/bin/nerve-hub": true,
        "/home/me/.cargo/bin/nerve-hub": true,
      }),
      "/home/me",
    );
    assert.equal(found, "/opt/homebrew/bin/nerve-hub");
  });

  test("falls through to PATH", () => {
    const found = locateHub(probe({}, "/usr/bin/nerve-hub"), "/home/me");
    assert.equal(found, "/usr/bin/nerve-hub");
  });

  test("missing is undefined", () => {
    assert.equal(locateHub(probe({}), "/home/me"), undefined);
  });
});
