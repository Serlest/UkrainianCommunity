/** Server-controlled WebAuthn origins; never accept an origin from a callable request. */
export function passkeyOrigins(androidOrigins: string | undefined): string[] {
  const web = "https://ukrainiancommunity-dbd5f.web.app";
  if (!androidOrigins?.trim()) return [web];
  const origins = androidOrigins.split(",").map((value) => value.trim());
  if (origins.some((value) => !/^android:apk-key-hash:[A-Za-z0-9_-]{43}$/.test(value))) {
    throw new Error("Invalid UAC_PASSKEY_ANDROID_ORIGINS configuration");
  }
  return [web, ...new Set(origins)];
}
