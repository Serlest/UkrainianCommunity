const productionRpId = "ukrainiancommunity-dbd5f.web.app";
const stagingProjectId = "uac-android-test-20260903";
const stagingRpId = "uac-android-test-20260903.web.app";

/** The isolated test backend uses its own Hosting domain; production stays pinned. */
export function passkeyRpId(projectId: string | undefined, configured: string | undefined): string {
  if (!configured?.trim()) return productionRpId;
  if (projectId !== stagingProjectId || configured !== stagingRpId) {
    throw new Error("Invalid UAC_PASSKEY_RP_ID configuration");
  }
  return stagingRpId;
}

/** Server-controlled WebAuthn origins; never accept an origin from a callable request. */
export function passkeyOrigins(androidOrigins: string | undefined, rpId = productionRpId): string[] {
  if (rpId !== productionRpId && rpId !== stagingRpId) {
    throw new Error("Invalid passkey RP ID");
  }
  const web = `https://${rpId}`;
  if (!androidOrigins?.trim()) return [web];
  const origins = androidOrigins.split(",").map((value) => value.trim());
  if (origins.some((value) => !/^android:apk-key-hash:[A-Za-z0-9_-]{43}$/.test(value))) {
    throw new Error("Invalid UAC_PASSKEY_ANDROID_ORIGINS configuration");
  }
  return [web, ...new Set(origins)];
}
