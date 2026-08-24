import { strict as assert } from "node:assert";
import { jobInFolder, matchesFilter } from "../../src/model/filter";
import { parseJob, type Job } from "../../src/model/job";

function job(value: Record<string, unknown>): Job {
  const parsed = parseJob({ id: "a", ...value });
  if (!parsed) throw new Error("parseJob rejected a test fixture");
  return parsed;
}

suite("filter", () => {
  test("this folder matches workspace prefix", () => {
    const row = job({ context: { workspace: "/Users/me/work/nerve" } });
    assert.equal(jobInFolder(row, ["/Users/me/work/nerve"]), true);
    assert.equal(jobInFolder(row, ["/Users/me/work/other"]), false);
    assert.equal(
      jobInFolder(
        job({ context: { workspace: "/Users/me/work/nerve-extra" } }),
        ["/Users/me/work/nerve"],
      ),
      false,
    );
  });

  test("attention filter includes problem", () => {
    assert.equal(
      matchesFilter(
        job({ lifecycle: "active", outcome: "failure" }),
        "attention",
        [],
      ),
      true,
    );
    assert.equal(
      matchesFilter(job({ lifecycle: "active" }), "attention", []),
      false,
    );
  });

  test("all is unfiltered", () => {
    assert.equal(matchesFilter(job({ lifecycle: "active" }), "all", []), true);
  });
});
