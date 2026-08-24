import { strict as assert } from "node:assert";
import { bestHost, parseSshConfig, scoreHost } from "../../src/focus/ssh";

suite("ssh config", () => {
  test("reads literal Host / HostName pairs and skips patterns", () => {
    const hosts = parseSshConfig(`
Host Arrhenius
  HostName arrhenius1.example
Host *.internal
  HostName ignore.me
Host dardel
`);
    assert.deepEqual(hosts, [
      { alias: "Arrhenius", hostName: "arrhenius1.example" },
      { alias: "dardel", hostName: "dardel" },
    ]);
  });

  test("bestHost prefers exact then label then prefix", () => {
    const hosts = [
      { alias: "hpc", hostName: "arrhenius1" },
      { alias: "dardel", hostName: "dardel.pdc.kth.se" },
    ];
    assert.equal(bestHost("arrhenius1", hosts), "hpc");
    assert.equal(bestHost("dardel", hosts), "dardel");
    assert.equal(bestHost("beskow", hosts), undefined);
  });

  test("a three-letter prefix is the floor", () => {
    assert.equal(scoreHost("ab", "abc"), undefined);
    assert.equal(scoreHost("Arrhenius", "arrhenius1"), 1);
    assert.equal(scoreHost("arrhenius1", "arrhenius1"), 3);
  });
});
