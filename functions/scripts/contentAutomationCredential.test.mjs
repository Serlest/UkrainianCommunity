import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  DEFAULT_CONTENT_AUTOMATION_ACCOUNT_EMAIL,
  contentAutomationAccessToken,
  contentAutomationAccountEmail,
  contentAutomationCredential,
  decodeSuccessfulJSON,
} from "./contentAutomationCredential.mjs";

test("uses the production operator account by default", async () => {
  assert.equal(
    contentAutomationAccountEmail({}),
    DEFAULT_CONTENT_AUTOMATION_ACCOUNT_EMAIL
  );
});

test("allows an explicit automation account override", async () => {
  assert.equal(
    contentAutomationAccountEmail({
      UAC_FIREBASE_ACCOUNT_EMAIL: " automation@example.com ",
    }),
    "automation@example.com"
  );
});

test("requests the selected Firebase CLI account", async () => {
  let requestedEmail;
  const credential = await contentAutomationCredential({
    environment: {UAC_FIREBASE_ACCOUNT_EMAIL: "operator@example.com"},
    createCredential: async ({accountEmail}) => {
      requestedEmail = accountEmail;
      return {accountEmail, getAccessToken: async () => ({access_token: "token"})};
    },
  });

  assert.equal(requestedEmail, "operator@example.com");
  assert.equal(credential.accountEmail, "operator@example.com");
});

test("returns only the short-lived access token", async () => {
  const accessToken = await contentAutomationAccessToken({
    environment: {},
    createCredential: async () => ({
      getAccessToken: async () => ({
        access_token: "short-lived-access-token",
        expires_in: 1800,
      }),
    }),
  });

  assert.equal(accessToken, "short-lived-access-token");
});

test("does not reinterpret an authorization failure as an empty result", async () => {
  const response = new Response(
    JSON.stringify({error: {message: "Permission denied for this account."}}),
    {status: 403, headers: {"Content-Type": "application/json"}}
  );

  await assert.rejects(
    decodeSuccessfulJSON(response, "App owner lookup"),
    /App owner lookup failed \(403\): Permission denied/
  );
});

test("decodes a successful JSON response", async () => {
  const response = new Response(JSON.stringify([{document: {name: "owner"}}]), {
    status: 200,
    headers: {"Content-Type": "application/json"},
  });

  assert.deepEqual(
    await decodeSuccessfulJSON(response, "App owner lookup"),
    [{document: {name: "owner"}}]
  );
});
