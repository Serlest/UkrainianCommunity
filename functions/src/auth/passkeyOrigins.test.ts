import {strict as assert} from "node:assert";
import {test} from "node:test";
import {passkeyOrigins} from "./passkeyOrigins";

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
