export function isSystemLogAppAdminReadable(data) {
  const readableCategories = new Set([
    "userAccount", "organization", "moderation", "diagnostics",
  ]);
  const securitySensitive = data?.retentionPolicy === "security"
    || data?.category === "authorization"
    || ["permissionDenied", "accountBlocked"].includes(data?.eventType);
  const ownerTarget = data?.targetActorRole === "owner" || data?.targetRole === "owner";

  return readableCategories.has(data?.category)
    && !securitySensitive
    && data?.actorRole !== "owner"
    && !ownerTarget;
}
