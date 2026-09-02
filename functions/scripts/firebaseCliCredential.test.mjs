import {strict as assert} from "node:assert";
import {test} from "node:test";

import {firebaseCliCredential} from "./firebaseCliCredential.mjs";

const validLogin = JSON.stringify({
  result: [{
    user: {email: "owner@example.com"},
    tokens: {refresh_token: "refresh-token-long-enough-for-test"},
  }],
});

test("returns a short-lived credential without exposing the refresh token", async () => {
  let refreshCalls = 0;
  let receivedRefreshToken;
  let receivedScopes;
  const credential = await firebaseCliCredential({
    runFirebaseLogin: () => validLogin,
    loadFirebaseAuth: () => ({
      getAccessToken: async (refreshToken, scopes) => {
        refreshCalls += 1;
        receivedRefreshToken = refreshToken;
        receivedScopes = scopes;
        return {access_token: "access-token-long-enough-for-test", expires_in: 1800};
      },
    }),
    now: () => 1_000,
  });

  assert.deepEqual(await credential.getAccessToken(), {
    access_token: "access-token-long-enough-for-test",
    expires_in: 1800,
  });
  assert.deepEqual(await credential.getAccessToken(), {
    access_token: "access-token-long-enough-for-test",
    expires_in: 1800,
  });
  assert.equal(refreshCalls, 1);
  assert.equal(receivedRefreshToken, "refresh-token-long-enough-for-test");
  assert.deepEqual(receivedScopes, []);
  assert.equal(credential.accountEmail, "owner@example.com");
});

test("fails closed when Firebase CLI has no usable refresh token", async () => {
  await assert.rejects(
    firebaseCliCredential({
      runFirebaseLogin: () => JSON.stringify({
        result: [{user: {email: "owner@example.com"}, tokens: {}}],
      }),
      loadFirebaseAuth: () => ({getAccessToken: async () => ({})}),
    }),
    /not authenticated/
  );
});

test("fails closed when token refresh returns unusable data", async () => {
  const credential = await firebaseCliCredential({
    runFirebaseLogin: () => validLogin,
    loadFirebaseAuth: () => ({getAccessToken: async () => ({access_token: "short"})}),
  });
  await assert.rejects(credential.getAccessToken(), /access token is unavailable/);
});

test("rejects malformed Firebase CLI output without leaking its contents", async () => {
  await assert.rejects(
    firebaseCliCredential({
      runFirebaseLogin: () => "not-json-with-sensitive-data",
    }),
    {message: "Firebase CLI returned invalid authentication data."}
  );
});
