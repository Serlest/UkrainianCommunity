import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {FieldPath, FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

const args = new Set(process.argv.slice(2));
const projectArgument = process.argv.find((value) => value.startsWith("--project="));
const projectId = projectArgument?.slice("--project=".length);
const apply = args.has("--apply");

if (!projectId) {
  throw new Error("Use --project=<firebase-project-id>. Dry-run is the default; add --apply to write.");
}

const app = initializeApp({credential: applicationDefault(), projectId}, `notification-inbox-invariant-${Date.now()}`);
try {
  const db = getFirestore(app);
  const usersQuery = db.collection("users")
    .orderBy(FieldPath.documentId())
    .limit(400);
  let userCursor;
  let usersScanned = 0;
  let unreadScanned = 0;
  let changeCount = 0;

  while (true) {
    const usersSnapshot = await (userCursor ? usersQuery.startAfter(userCursor) : usersQuery).get();
    if (usersSnapshot.empty) break;
    usersScanned += usersSnapshot.size;

    for (const userDocument of usersSnapshot.docs) {
      const inboxQuery = userDocument.ref.collection("notificationInbox")
        .where("isRead", "==", false)
        .orderBy(FieldPath.documentId())
        .limit(400);
      let inboxCursor;

      while (true) {
        const inboxSnapshot = await (inboxCursor ? inboxQuery.startAfter(inboxCursor) : inboxQuery).get();
        if (inboxSnapshot.empty) break;
        unreadScanned += inboxSnapshot.size;
        const changes = inboxSnapshot.docs.flatMap(changeFor);
        changeCount += changes.length;

        if (apply && changes.length > 0) {
          const batch = db.batch();
          for (const change of changes) batch.update(change.reference, change.update);
          await batch.commit();
        }

        inboxCursor = inboxSnapshot.docs.at(-1);
        if (inboxSnapshot.size < 400) break;
      }
    }

    userCursor = usersSnapshot.docs.at(-1);
    if (usersSnapshot.size < 400) break;
  }

  console.log(JSON.stringify({
    projectId,
    usersScanned,
    unreadScanned,
    changes: changeCount,
    apply,
  }));
} finally {
  await deleteApp(app);
}

function changeFor(document) {
  const data = document.data();
  const archivedAt = data.archivedAt;
  const deletedAt = data.deletedAt;
  const isArchivedOrDeleted = archivedAt != null || deletedAt != null;
  const missingVisibilityFields = !("archivedAt" in data) || !("deletedAt" in data);
  if (!isArchivedOrDeleted && !missingVisibilityFields) return [];

  if (isArchivedOrDeleted) {
    const existingDate = deletedAt instanceof Timestamp ? deletedAt : archivedAt;
    return [{
      reference: document.ref,
      update: {
        isRead: true,
        readAt: existingDate instanceof Timestamp ? existingDate : FieldValue.serverTimestamp(),
      },
    }];
  }

  return [{
    reference: document.ref,
    update: {
      archivedAt: null,
      deletedAt: null,
    },
  }];
}
