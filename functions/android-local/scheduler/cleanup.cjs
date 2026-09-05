"use strict";

async function cleanupOwned(db, manifest) {
  const failures = [];
  // Every target was durably registered before any mutation. No collection-wide deletion.
  for (const ownedPath of [...manifest.paths].reverse()) {
    try {
      const ref = db.doc(ownedPath);
      // A prepared run never owned existing documents: on collision/interruption only prove absence.
      if (manifest.phase === "active") await ref.delete();
      if ((await ref.get()).exists) throw new Error("Exact scheduler fixture cleanup read-back failed.");
    } catch (error) { failures.push(error); }
  }
  if (failures.length) throw new AggregateError(failures, "Scheduler fixture cleanup incomplete; manifest retained.");
  require("./registry.cjs").removeAfterReadback(manifest);
}

module.exports = {cleanupOwned};

if (require.main === module) {
  (async () => {
    const boundary = require("./boundary.cjs");
    const registry = require("./registry.cjs");
    const manifest = registry.read();
    if (process.env.UAC_SCHEDULER_MODE !== "cleanup" || registry.ownerAlive(manifest)) {
      throw new Error("Cleanup requires explicit mode and the previous runner to be absent.");
    }
    if (manifest.phase === "active") boundary.installRegistry(manifest);
    await cleanupOwned(boundary.db, manifest);
    if (boundary.snapshot().blockedAttempts !== 0) throw new Error("Cleanup violated the local boundary.");
    await boundary.db.terminate();
    console.log("Scheduler exact cleanup/read-back confirmed; manifest removed.");
  })().catch(error => { console.error(error.message); process.exitCode = 1; });
}
