import { strict as assert } from "node:assert";
import { parseFrame } from "../../src/model/job";
import { JobStore } from "../../src/store/jobStore";

suite("job store", () => {
  test("a frame replaces the set", () => {
    const store = new JobStore();
    store.applyFrame(
      parseFrame(JSON.stringify({ jobs: [{ id: "a" }, { id: "b" }] })),
    );
    assert.equal(store.snapshot().jobs.length, 2);
    store.applyFrame(parseFrame(JSON.stringify({ jobs: [{ id: "c" }] })));
    assert.deepEqual(
      store.snapshot().jobs.map((job) => job.id),
      ["c"],
    );
    assert.equal(store.snapshot().connected, true);
  });

  test("offline keeps the last jobs", () => {
    const store = new JobStore();
    store.applyJobs(
      parseFrame(JSON.stringify({ jobs: [{ id: "a" }] })).jobs,
    );
    store.setOffline();
    assert.equal(store.snapshot().connected, false);
    assert.equal(store.snapshot().jobs[0]?.id, "a");
  });
});
