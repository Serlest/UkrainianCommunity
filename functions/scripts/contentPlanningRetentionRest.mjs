const retentionPolicy = "contentPlanningReceipt6Months";

export function decodeFirestoreDocument(document) {
  if (!document || typeof document.name !== "string" ||
      typeof document.updateTime !== "string") {
    throw new Error("Firestore returned an invalid content planning document.");
  }
  return {
    name: document.name,
    path: document.name.split("/documents/")[1] ?? document.name,
    updateTime: document.updateTime,
    data: Object.fromEntries(
      Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)])
    ),
  };
}

export function buildContentPlanningRetentionWrite(item) {
  const result = item?.result;
  const draft = item?.draft;
  if (result?.status !== "update" || typeof draft?.name !== "string" ||
      typeof draft?.updateTime !== "string" ||
      !Number.isFinite(result.retentionExpiresAtMilliseconds)) {
    throw new Error("Retention write requires a classified Firestore document.");
  }
  const fields = {
    retentionExpiresAt: {
      timestampValue: new Date(result.retentionExpiresAtMilliseconds).toISOString(),
    },
    retentionPolicy: {stringValue: retentionPolicy},
  };
  const fieldPaths = ["retentionExpiresAt", "retentionPolicy"];
  const write = {
    update: {name: draft.name, fields},
    updateMask: {fieldPaths},
    currentDocument: {updateTime: draft.updateTime},
  };
  if (!nonEmptyString(draft.data?.draftMediaCleanupStatus)) {
    fields.draftMediaCleanupStatus = {stringValue: result.mediaCleanupStatus};
    fieldPaths.push("draftMediaCleanupStatus");
    if (result.requestsMediaCleanup) {
      write.updateTransforms = [{
        fieldPath: "draftMediaCleanupRequestedAt",
        setToServerValue: "REQUEST_TIME",
      }];
    }
  }
  return write;
}

export function verifyContentPlanningRetentionReadBack(document, expected) {
  const draft = decodeFirestoreDocument(document);
  const expiry = Date.parse(draft.data.retentionExpiresAt);
  const cleanupStatus = nonEmptyString(draft.data.draftMediaCleanupStatus);
  return Number.isFinite(expiry) &&
    expiry === expected.retentionExpiresAtMilliseconds &&
    draft.data.retentionPolicy === retentionPolicy &&
    Boolean(cleanupStatus);
}

function decodeValue(value) {
  if (!value || typeof value !== "object") return undefined;
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decodeValue(item)])
    );
  }
  return undefined;
}

function nonEmptyString(value) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}
