import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

import {isSystemLogAppAdminReadable} from "./systemLogVisibilityCore.mjs";

const args = new Set(process.argv.slice(2));
const projectArgument = process.argv.find((value) => value.startsWith("--project="));
const projectId = projectArgument?.slice("--project=".length);
const apply = args.has("--apply");

if (!projectId) {
  throw new Error("Use --project=<firebase-project-id>. Dry-run is the default; add --apply to write.");
}

const app = initializeApp({credential: applicationDefault(), projectId}, `system-log-visibility-${Date.now()}`);
try {
  const db = getFirestore(app);
  const snapshot = await db.collection("systemLogs").get();
  const changes = snapshot.docs.filter((document) => {
    const data = document.data();
    return data.isAppAdminReadable !== isSystemLogAppAdminReadable(data);
  });

  console.log(JSON.stringify({projectId, scanned: snapshot.size, changes: changes.length, apply}));
  if (apply) {
    for (let index = 0; index < changes.length; index += 400) {
      const batch = db.batch();
      for (const document of changes.slice(index, index + 400)) {
        batch.update(document.ref, {
          isAppAdminReadable: isSystemLogAppAdminReadable(document.data()),
        });
      }
      await batch.commit();
    }
  }
} finally {
  await deleteApp(app);
}
