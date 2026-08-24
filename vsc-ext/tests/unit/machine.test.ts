import { strict as assert } from "node:assert";
import { foreignAlias, sameAlias, sanitizeAlias } from "../../src/model/machine";

suite("machine alias", () => {
  test("same alias is case-insensitive and stripped of punctuation", () => {
    assert.equal(sameAlias("RoydeMacBook-Air", "roydemacbook-air"), true);
    assert.equal(sameAlias(" arrhenius1 ", "arrhenius1"), true);
    assert.equal(sameAlias("Roy's-Air", "Roys-Air"), true);
    assert.equal(sameAlias("arrhenius1", "arrhenius2"), false);
  });

  test("foreignAlias is none when this machine has no name", () => {
    assert.equal(foreignAlias("arrhenius1", undefined), undefined);
  });

  test("foreignAlias is none when the job is local", () => {
    assert.equal(foreignAlias("box", "box"), undefined);
  });

  test("foreignAlias returns the job alias when it differs", () => {
    assert.equal(foreignAlias("arrhenius1", "macbook"), "arrhenius1");
  });

  test("sanitize drops apostrophes", () => {
    assert.equal(sanitizeAlias("Roy's-Air"), "Roys-Air");
  });
});
