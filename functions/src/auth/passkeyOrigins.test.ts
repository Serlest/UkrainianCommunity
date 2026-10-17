import {strict as assert} from "node:assert";
import {test} from "node:test";
import {passkeyOrigins, passkeyRpId} from "./passkeyOrigins";

test("web passkeys remain accepted without Android configuration", () => {
  assert.deepEqual(passkeyOrigins(undefined), ["https://ukrainiancommunity-dbd5f.web.app"]);
});

test("only configured Android certificate origins are accepted", () => {
  const origin = `android:apk-key-hash:${"A".repeat(43)}`;
  assert.deepEqual(passkeyOrigins(`${origin}, ${origin}`), [
    "https://ukrainiancommunity-dbd5f.web.app", origin,
  ]);
  assert.throws(() => passkeyOrigins("android:apk-key-hash:unverified"));
  assert.throws(() => passkeyOrigins("https://untrusted.example"));
});

test("staging has a separate RP domain and production cannot select it", () => {
  const staging = passkeyRpId("uac-android-test-20260903", "uac-android-test-20260903.web.app");
  assert.equal(staging, "uac-android-test-20260903.web.app");
  assert.deepEqual(passkeyOrigins(undefined, staging), ["https://uac-android-test-20260903.web.app"]);
  assert.equal(passkeyRpId("ukrainiancommunity-dbd5f", undefined), "ukrainiancommunity-dbd5f.web.app");
  assert.throws(() => passkeyRpId("ukrainiancommunity-dbd5f", staging));
  assert.throws(() => passkeyRpId("uac-android-test-20260903", "arbitrary.example"));
  assert.throws(() => passkeyOrigins(undefined, "arbitrary.example"));
});
