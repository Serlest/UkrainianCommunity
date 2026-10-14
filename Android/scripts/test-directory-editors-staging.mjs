import {execFileSync, spawnSync} from "node:child_process";
import {createHmac, randomBytes, randomUUID} from "node:crypto";

// Disposable test-project only. No production project argument is accepted.
const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const suffix = randomBytes(8).toString("hex");
const categoryId = `custom-${randomUUID()}`;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const oauth = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", [
  "apps:sdkconfig", "ANDROID", appId, "--project", project,
], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong Firebase project");
const key = config.client?.[0]?.api_key?.[0]?.current_key;
if (!key) throw new Error("Staging API key unavailable");
const accounts = [];
let installed = false;
let debugTokenId = null;

async function call(url, method = "GET", body, token = oauth) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(token ? {authorization: `Bearer ${token}`, "x-goog-user-project": project} : {}),
      ...(body === undefined ? {} : {"content-type": "application/json"}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return {status: response.status, data: await response.json().catch(() => ({}))};
}
function expect(response, status, label) {
  if (response.status !== status)
    throw new Error(`${label}: HTTP ${response.status} ${response.data.error?.status ?? ""} ${response.data.error?.message ?? ""}`);
  return response.data;
}
function value(input) {
  if (typeof input === "string") return {stringValue: input};
  if (typeof input === "boolean") return {booleanValue: input};
  if (input instanceof Date) return {timestampValue: input.toISOString()};
  throw new Error("Unexpected fixture field");
}
function fields(input) {
  return Object.fromEntries(Object.entries(input).map(([name, item]) => [name, value(item)]));
}
function read(field) {
  return field?.stringValue ?? field?.booleanValue ?? field?.integerValue ?? field?.timestampValue ?? null;
}
async function document(path) { return call(`${base}/${path}`); }
async function createDocument(path, object) {
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(object)}), 200, `create ${path}`);
}
async function user(role, terms, privacy) {
  const email = `directory-step2-${suffix}-${role}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `signup ${role}`);
  const uid = signup.localId;
  accounts.push({uid, email, password, role});
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: uid, emailVerified: true}), 200, `verify ${role}`);
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `login ${role}`);
  await createDocument(`users/${uid}`, {
    email, displayName: `Directory step2 ${role}`, globalRole: role === "owner" ? "owner" : "user",
    accountStatus: "active", blockState: "active", requiresMultiFactorAuth: role === "owner",
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy, createdAt: new Date(),
  });
  return {uid, email, password, idToken: login.idToken};
}
function decodeBase32(secret) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0; let count = 0; const bytes = [];
  for (const char of secret.replaceAll("=", "").toUpperCase()) {
    const digit = alphabet.indexOf(char);
    if (digit < 0) throw new Error("Invalid TOTP secret");
    bits = (bits << 5) | digit; count += 5;
    if (count >= 8) {count -= 8; bytes.push((bits >> count) & 255);}
  }
  return Buffer.from(bytes);
}
function totp(secret, period, digits, at = Date.now()) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at / 1_000 / period)));
  const digest = createHmac("sha1", decodeBase32(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % (10 ** digits)).padStart(digits, "0");
}
async function enrollOwner(owner) {
  const started = expect(await call(`${authBase}/v2/accounts/mfaEnrollment:start?key=${key}`, "POST",
    {idToken: owner.idToken, totpEnrollmentInfo: {}}, ""), 200, "start TOTP");
  const info = started.totpSessionInfo;
  if (!info?.sharedSecretKey || !info?.sessionInfo) throw new Error("Missing TOTP enrollment");
  const factor = {secret: info.sharedSecretKey, period: info.periodSec ?? 30,
    digits: info.verificationCodeLength ?? 6, usedCounter: 0};
  expect(await call(`${authBase}/v2/accounts/mfaEnrollment:finalize?key=${key}`, "POST", {
    idToken: owner.idToken, displayName: "Staging owner proof",
    totpVerificationInfo: {sessionInfo: info.sessionInfo,
      verificationCode: totp(factor.secret, factor.period, factor.digits)},
  }, ""), 200, "enroll TOTP");
  const challenged = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`,
    "POST", {email: owner.email, password: owner.password, returnSecureToken: true}, ""), 200,
  "challenge owner");
  if (!challenged.mfaPendingCredential || !challenged.mfaInfo?.[0]?.mfaEnrollmentId || challenged.idToken)
    throw new Error("Owner password login did not require MFA");
  const wait = (factor.period - Date.now() / 1_000 % factor.period + 1) * 1_000;
  await new Promise((resolve) => setTimeout(resolve, wait));
  const signInAt = Date.now();
  const completed = expect(await call(`${authBase}/v2/accounts/mfaSignIn:finalize?key=${key}`,
    "POST", {mfaPendingCredential: challenged.mfaPendingCredential,
      mfaEnrollmentId: challenged.mfaInfo[0].mfaEnrollmentId,
      totpVerificationInfo: {verificationCode: totp(factor.secret, factor.period, factor.digits, signInAt)}},
  ""), 200, "complete owner TOTP");
  const token = JSON.parse(Buffer.from(completed.idToken.split(".")[1], "base64url").toString());
  if (token.firebase?.sign_in_second_factor !== "totp") throw new Error("No real TOTP token claim");
  factor.usedCounter = Math.floor(signInAt / 1_000 / factor.period);
  return {factor, idToken: completed.idToken};
}
function invoke(name, token, payload) {
  return call(`https://europe-west3-${project}.cloudfunctions.net/${name}`, "POST", {data: payload}, token);
}
function payload(title) {
  return JSON.stringify({
    id: categoryId, placement: "start", order: 900, isHidden: false, symbol: "book",
    title: {ukrainian: "Тест довідника", german: title},
    summary: {ukrainian: "Тестовий опис", german: "Testbeschreibung"},
    groups: [{id: "general", title: {ukrainian: "Основне", german: "Allgemein"}, order: 0, isHidden: false}],
    topics: [{id: "test-topic", groupID: "general", order: 0, isHidden: false,
      title: {ukrainian: "Тема", german: "Thema"},
      summary: {ukrainian: "Вступ", german: "Einleitung"},
      sections: [{id: "test-section", order: 0, isHidden: false,
        title: {ukrainian: "Крок", german: "Schritt"},
        body: {ukrainian: "Пояснення", german: "Erklärung"}, symbol: "text.book.closed.fill",
        phoneNumber: null, source: null, contacts: []}],
      sources: [{name: "Official source", url: "https://www.oesterreich.gv.at/"}], regionalSections: {}}],
  });
}
function runUi(method, owner, editor, reader, factor) {
  const client = config.client[0];
  const web = client.oauth_client?.find((entry) => entry.client_type === 3)?.client_id;
  const android = client.oauth_client?.find((entry) => entry.client_type === 1 &&
    entry.android_info?.package_name === "at.serlest.ukrainiancommunity.staging");
  const env = {...process.env, ANDROID_SERIAL: "emulator-5580",
    UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key,
    UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket,
    UAC_STAGING_GOOGLE_WEB_CLIENT_ID: web && android ? web : ""};
  if (!installed) {
    const built = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
      "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
      encoding: "utf8", maxBuffer: 4_000_000});
    if (built.status !== 0) throw new Error(`Staging test APK build failed: ${built.status}`);
    const apks = ["app/build/outputs/apk/staging/debug/app-staging-debug.apk",
      "app/build/outputs/apk/androidTest/staging/debug/app-staging-debug-androidTest.apk"];
    for (const apk of apks) {
      const result = spawnSync("adb", ["-s", "emulator-5580", "install", "-r", apk],
        {cwd: new URL("..", import.meta.url), encoding: "utf8"});
      if (result.status !== 0 || !result.stdout.includes("Success"))
        throw new Error(`Staging test APK install failed: ${result.status}`);
    }
    installed = true;
    spawnSync("adb", ["-s", "emulator-5580", "logcat", "-c"]);
    const launched = spawnSync("adb", ["-s", "emulator-5580", "shell", "am", "start", "-n",
      "at.serlest.ukrainiancommunity.staging/at.uac.android.MainActivity"], {encoding: "utf8"});
    if (launched.status !== 0) throw new Error("Staging app failed to launch");
    let secret = "";
    for (let attempt = 0; attempt < 20 && !secret; attempt++) {
      const logs = spawnSync("adb", ["-s", "emulator-5580", "logcat", "-d", "-s",
        "com.google.firebase.appcheck.debug.internal.DebugAppCheckProvider:D"], {encoding: "utf8"});
      secret = logs.stdout.match(/Firebase App Check debug token: ([a-f0-9-]{36})/)?.[1] ?? "";
      if (!secret) spawnSync("sleep", ["1"]);
    }
    if (!secret) throw new Error("Staging App Check debug token was not generated");
    const name = `UAC Android step2 ${suffix}`;
    const registration = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
      "--project", project, "--app", appId, "--display-name", name],
    {encoding: "utf8"});
    if (registration.status !== 0) throw new Error("Staging App Check debug token registration failed");
    const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
      "--app", appId], {encoding: "utf8"});
    if (listed.status !== 0) throw new Error("Staging App Check debug token lookup failed");
    debugTokenId = listed.stdout.match(new RegExp(`UAC Android step2 ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1] ?? null;
    if (!debugTokenId) throw new Error("Staging App Check debug token id unavailable");
    spawnSync("adb", ["-s", "emulator-5580", "shell", "am", "force-stop",
      "at.serlest.ukrainiancommunity.staging"]);
    console.log("Registered disposable staging App Check token for this emulator");
  }
  const values = {
    class: `at.uac.android.StagingDirectoryEditorsJourneyTest#${method}`,
    directoryEditorUid: editor.uid, directoryCategoryId: categoryId,
    directoryOwnerEmail: owner.email, directoryOwnerPassword: owner.password,
    directoryOwnerSecret: factor.secret, directoryOwnerPeriod: String(factor.period),
    directoryOwnerDigits: String(factor.digits), directoryOwnerUsedCounter: String(factor.usedCounter),
    directoryEditorEmail: editor.email, directoryEditorPassword: editor.password,
    directoryReaderEmail: reader.email, directoryReaderPassword: reader.password,
  };
  const args = ["-s", "emulator-5580", "shell", "am", "instrument", "-w", "-r"];
  for (const [key, value] of Object.entries(values)) args.push("-e", key, value);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", args, {encoding: "utf8", maxBuffer: 4_000_000, timeout: 150_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter((line) =>
      /FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error/.test(line)).slice(0, 12).join("\n"));
    throw new Error(`Android staging ${method} failed: exit ${result.status}`);
  }
  factor.usedCounter = Math.floor(Date.now() / 1_000 / factor.period);
  console.log(`Android staging UI: ${method} passed`);
}

let passed = false;
try {
  const [terms, privacy] = await Promise.all([document("legalDocuments/terms"), document("legalDocuments/privacy")]);
  expect(terms, 200, "terms"); expect(privacy, 200, "privacy");
  const versions = [read(terms.data.fields.activeVersion), read(privacy.data.fields.activeVersion)];
  const owner = await user("owner", ...versions);
  const editor = await user("editor", ...versions);
  const reader = await user("reader", ...versions);
  const {factor, idToken} = await enrollOwner(owner);
  const denied = await call(`${base}:commit`, "POST", {writes: [{
    update: {name: `projects/${project}/databases/(default)/documents/directoryEditors/${editor.uid}`,
      fields: fields({enabled: true, grantedBy: reader.uid})},
    updateTransforms: [{fieldPath: "grantedAt", setToServerValue: "REQUEST_TIME"}],
    currentDocument: {exists: false},
  }]}, reader.idToken);
  if (denied.status !== 403) throw new Error(`Reader grant write not denied: HTTP ${denied.status}`);
  if ((await document(`directoryEditors/${editor.uid}`)).status !== 404)
    throw new Error("Denied grant unexpectedly exists");
  runUi("readerCannotOpenGrantScreen", owner, editor, reader, factor);
  runUi("ownerGrantsEditor", owner, editor, reader, factor);
  const grant = expect(await document(`directoryEditors/${editor.uid}`), 200, "grant readback");
  if (read(grant.fields.enabled) !== true || read(grant.fields.grantedBy) !== owner.uid ||
      !grant.fields.grantedAt?.timestampValue || Object.keys(grant.fields).sort().join() !==
      "enabled,grantedAt,grantedBy") throw new Error("Grant is not iOS-compatible");
  const first = expect(await invoke("saveDirectoryCategory", idToken,
    {categoryId, payload: payload("Staging original"), expectedRevision: 0}), 200, "owner category seed");
  if (first.result?.revision !== 1) throw new Error("Seed revision mismatch");
  const editorPreflight = await invoke("saveDirectoryCategory", editor.idToken,
    {categoryId, payload: payload("Preflight"), expectedRevision: 99});
  if (editorPreflight.status !== 409 || editorPreflight.data.error?.status !== "ABORTED")
    throw new Error(`Editor callable preflight failed: HTTP ${editorPreflight.status} ${editorPreflight.data.error?.status ?? ""}`);
  try {
    runUi("editorPublishesCategory", owner, editor, reader, factor);
  } catch (error) {
    const current = await document(`directoryCategories/${categoryId}`);
    console.error(`Editor publish diagnostic: server revision ${read(current.data.fields?.revision) ?? "missing"}`);
    throw error;
  }
  const current = expect(await document(`directoryCategories/${categoryId}`), 200, "category readback");
  const version1 = expect(await document(`directoryCategories/${categoryId}/versions/1`), 200, "history 1");
  const version2 = expect(await document(`directoryCategories/${categoryId}/versions/2`), 200, "history 2");
  if (read(current.fields.revision) !== "2" || read(current.fields.updatedBy) !== editor.uid ||
      JSON.parse(read(current.fields.payload)).title.german !== "Staging redigiert" ||
      read(version1.fields.revision) !== "1" || read(version2.fields.revision) !== "2" ||
      read(version2.fields.updatedBy) !== editor.uid)
    throw new Error("Directory category revision/history readback failed");
  const stale = await invoke("saveDirectoryCategory", editor.idToken,
    {categoryId, payload: payload("Stale"), expectedRevision: 1});
  if (stale.status !== 409 || stale.data.error?.status !== "ABORTED")
    throw new Error(`Stale revision not rejected: HTTP ${stale.status}`);
  runUi("ownerRevokesEditor", owner, editor, reader, factor);
  if ((await document(`directoryEditors/${editor.uid}`)).status !== 404)
    throw new Error("Revoked grant still exists");
  const revoked = await invoke("saveDirectoryCategory", editor.idToken,
    {categoryId, payload: payload("Revoked"), expectedRevision: 2});
  if (revoked.status !== 403 || revoked.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Revoked editor was not denied: HTTP ${revoked.status}`);
  passed = true;
  console.log("Staging directory editors: owner TOTP UI grant/revoke, editor UI publish, role denial, revision/history readback passed");
} finally {
  const paths = [`directoryEditors/${accounts.find((item) => item.role === "editor")?.uid}`,
    `directoryCategories/${categoryId}/versions/2`,
    `directoryCategories/${categoryId}/versions/1`, `directoryCategories/${categoryId}`];
  for (const path of paths) {
    if (path.endsWith("undefined")) continue;
    const prior = await document(path);
    if (prior.status === 200) expect(await call(`${base}/${path}`, "DELETE"), 200, `cleanup ${path}`);
    else if (prior.status !== 404) throw new Error(`Cleanup read failed for ${path}`);
    if ((await document(path)).status !== 404) throw new Error(`Cleanup readback failed for ${path}`);
  }
  for (const account of accounts) {
    const profile = await document(`publicProfiles/${account.uid}`);
    if (profile.status === 200) expect(await call(`${base}/publicProfiles/${account.uid}`, "DELETE"), 200, "cleanup public profile");
    else if (profile.status !== 404) throw new Error("Public profile cleanup read failed");
    if ((await document(`publicProfiles/${account.uid}`)).status !== 404)
      throw new Error("Public profile cleanup readback failed");
    const userProfile = await document(`users/${account.uid}`);
    if (userProfile.status === 200)
      expect(await call(`${base}/users/${account.uid}`, "DELETE"), 200, "cleanup user profile");
    else if (userProfile.status !== 404) throw new Error("User profile cleanup read failed");
    if ((await document(`users/${account.uid}`)).status !== 404) throw new Error("User profile cleanup failed");
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST", {localId: account.uid}),
      200, "cleanup Auth user");
    const lookup = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST",
      {localId: [account.uid]}), 200, "Auth cleanup readback");
    if ((lookup.users ?? []).length) throw new Error("Auth user cleanup failed");
  }
  if (!debugTokenId && installed) {
    const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
      "--app", appId], {encoding: "utf8"});
    debugTokenId = listed.stdout.match(new RegExp(`UAC Android step2 ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1] ?? null;
  }
  if (debugTokenId) {
    const deleted = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (deleted.status !== 0) throw new Error("Staging App Check debug token cleanup failed");
  }
  if (installed) {
    for (const packageName of ["at.serlest.ukrainiancommunity.staging.test",
      "at.serlest.ukrainiancommunity.staging"]) {
      const removed = spawnSync("adb", ["-s", "emulator-5580", "uninstall", packageName],
        {encoding: "utf8"});
      if (removed.status !== 0) throw new Error("Staging emulator package cleanup failed");
    }
  }
  console.log(`Staging directory cleanup: ${accounts.length} Auth users and category removed${passed ? "" : " after failure"}`);
}
