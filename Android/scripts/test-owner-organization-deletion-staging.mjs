import {execFileSync, spawnSync} from "node:child_process";
import {createHmac, randomBytes} from "node:crypto";

// Disposable fixtures and deployment checks are restricted to this test project.
const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5582";
const suffix = randomBytes(8).toString("hex");
const orgId = `step5-owner-delete-${suffix}`;
const newsId = `step5-owner-delete-news-${suffix}`;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId,
  "--project", project], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong staging project");
const client = config.client?.[0];
const key = client?.api_key?.[0]?.current_key;
if (!key) throw new Error("Missing staging API key");
const accounts = {};
const paths = new Set();
let debugTokenId;
let installed = false;

async function call(url, method = "GET", body, bearer = token) {
  const response = await fetch(url, {method, headers: {
    ...(bearer ? {authorization: `Bearer ${bearer}`, "x-goog-user-project": project} : {}),
    ...(body === undefined ? {} : {"content-type": "application/json"}),
  }, body: body === undefined ? undefined : JSON.stringify(body)});
  return {status: response.status, data: await response.json().catch(() => ({}))};
}
function expect(result, status, label) {
  if (result.status !== status) throw new Error(`${label}: HTTP ${result.status} ${result.data.error?.status ?? ""} ${result.data.error?.message ?? ""}`);
  return result.data;
}
function encode(value) {
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  throw new Error("Invalid fixture field");
}
const fields = row => Object.fromEntries(Object.entries(row).map(([name, value]) => [name, encode(value)]));
const read = field => field?.stringValue ?? field?.booleanValue ?? field?.integerValue ?? null;
const document = path => call(`${base}/${path}`);
async function list(path) {
  const result = await call(`${base}/${path}?pageSize=100`);
  return result.status === 404 ? [] : expect(result, 200, `list ${path}`).documents ?? [];
}
async function create(path, row) {
  paths.add(path);
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(row)}), 200, `create ${path}`);
}
async function remove(path) {
  const existing = await document(path);
  if (existing.status === 200) expect(await call(`${base}/${path}`, "DELETE"), 200, `remove ${path}`);
  else if (existing.status !== 404) throw new Error(`Read ${path}: HTTP ${existing.status}`);
  if ((await document(path)).status !== 404) throw new Error(`Cleanup failed ${path}`);
}
async function signup(role, terms, privacy) {
  const email = `org-delete-step5-${role}-${suffix}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const response = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `signup ${role}`);
  accounts[role] = {uid: response.localId, email, password, idToken: ""};
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: response.localId, emailVerified: true}), 200, `verify ${role}`);
  accounts[role].idToken = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`,
    "POST", {email, password, returnSecureToken: true}, ""), 200, `login ${role}`).idToken;
  await create(`users/${response.localId}`, {id: response.localId, email,
    displayName: `Step5 ${role} ${suffix}`, globalRole: role === "owner" ? "owner" : "user",
    accountStatus: "active", blockState: "active", requiresMultiFactorAuth: role === "owner",
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy, createdAt: new Date()});
}
function decodeBase32(secret) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0; let count = 0; const bytes = [];
  for (const char of secret.replaceAll("=", "")) {
    const digit = alphabet.indexOf(char);
    if (digit < 0) throw new Error("Invalid TOTP secret");
    bits = (bits << 5) | digit; count += 5;
    if (count >= 8) {count -= 8; bytes.push((bits >> count) & 255);}
  }
  return Buffer.from(bytes);
}
function totp(secret, period, digits, at = Date.now()) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at / 1000 / period)));
  const digest = createHmac("sha1", decodeBase32(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % (10 ** digits)).padStart(digits, "0");
}
async function enrollOwner() {
  const owner = accounts.owner;
  const started = expect(await call(`${authBase}/v2/accounts/mfaEnrollment:start?key=${key}`, "POST",
    {idToken: owner.idToken, totpEnrollmentInfo: {}}, ""), 200, "start TOTP");
  const info = started.totpSessionInfo;
  if (!info?.sharedSecretKey || !info?.sessionInfo) throw new Error("Missing TOTP enrollment");
  const factor = {secret: info.sharedSecretKey, period: info.periodSec ?? 30,
    digits: info.verificationCodeLength ?? 6, usedCounter: 0};
  expect(await call(`${authBase}/v2/accounts/mfaEnrollment:finalize?key=${key}`, "POST", {
    idToken: owner.idToken, displayName: "Step5 deletion proof",
    totpVerificationInfo: {sessionInfo: info.sessionInfo,
      verificationCode: totp(factor.secret, factor.period, factor.digits)},
  }, ""), 200, "enroll TOTP");
  const challenged = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`,
    "POST", {email: owner.email, password: owner.password, returnSecureToken: true}, ""), 200,
  "challenge owner");
  if (!challenged.mfaPendingCredential || !challenged.mfaInfo?.[0]?.mfaEnrollmentId || challenged.idToken)
    throw new Error("Owner login did not require MFA");
  const wait = (factor.period - Date.now() / 1000 % factor.period + 1) * 1000;
  await new Promise(resolve => setTimeout(resolve, wait));
  const signInAt = Date.now();
  const completed = expect(await call(`${authBase}/v2/accounts/mfaSignIn:finalize?key=${key}`,
    "POST", {mfaPendingCredential: challenged.mfaPendingCredential,
      mfaEnrollmentId: challenged.mfaInfo[0].mfaEnrollmentId,
      totpVerificationInfo: {verificationCode: totp(factor.secret, factor.period, factor.digits, signInAt)}},
  ""), 200, "complete TOTP");
  const claim = JSON.parse(Buffer.from(completed.idToken.split(".")[1], "base64url"));
  if (claim.firebase?.sign_in_second_factor !== "totp") throw new Error("No TOTP token claim");
  owner.idToken = completed.idToken;
  factor.usedCounter = Math.floor(signInAt / 1000 / factor.period);
  return factor;
}
function adb(args, timeout = 210_000) {
  const result = spawnSync("adb", ["-s", serial, ...args], {cwd: new URL("..", import.meta.url),
    encoding: "utf8", timeout, maxBuffer: 4_000_000});
  if (result.status !== 0) throw new Error(`adb failed: ${result.stderr?.trim()}`);
  return result.stdout;
}
async function setupApp() {
  const env = {...process.env, UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key, UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket};
  const built = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
    "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
    encoding: "utf8", maxBuffer: 4_000_000});
  if (built.status !== 0) throw new Error(`Staging build failed: ${built.stdout?.slice(-2500)} ${built.stderr?.slice(-900)}`);
  for (const apk of ["app/build/outputs/apk/staging/debug/app-staging-debug.apk",
    "app/build/outputs/apk/androidTest/staging/debug/app-staging-debug-androidTest.apk"])
    if (!adb(["install", "-r", apk]).includes("Success")) throw new Error(`Install failed: ${apk}`);
  installed = true;
  adb(["logcat", "-c"]);
  adb(["shell", "am", "start", "-n", "at.serlest.ukrainiancommunity.staging/at.uac.android.MainActivity"]);
  let secret = "";
  for (let index = 0; index < 20 && !secret; index++) {
    secret = adb(["logcat", "-d", "-s", "com.google.firebase.appcheck.debug.internal.DebugAppCheckProvider:D"])
      .match(/Firebase App Check debug token: ([a-f0-9-]{36})/)?.[1] ?? "";
    if (!secret) spawnSync("sleep", ["1"]);
  }
  if (!secret) throw new Error("App Check debug token absent");
  const prior = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  if (prior.status !== 0) throw new Error("App Check token lookup failed");
  const registered = [...prior.stdout.matchAll(/debugTokens\/([A-Za-z0-9_-]+)/g)]
    .some(([, resource]) => Buffer.from(resource, "base64url").toString() === secret);
  if (registered) {
    adb(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
    return;
  }
  const name = `UAC step5 org ${suffix}`;
  const added = await call(`https://firebaseappcheck.googleapis.com/v1/projects/966536981122/apps/${appId}/debugTokens`,
    "POST", {displayName: name, token: secret});
  if (added.status !== 200 && added.status !== 201)
    throw new Error(`App Check registration failed: HTTP ${added.status} ${added.data.error?.status ?? ""}`);
  debugTokenId = added.data.name?.split("/").at(-1);
  if (!debugTokenId) throw new Error("App Check debug token ID absent");
  adb(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
}
function runUi(method, factor) {
  const values = {class: `at.uac.android.StagingOrganizationDeletionJourneyTest#${method}`,
    deletionSuffix: suffix, memberEmail: accounts.member.email, memberPassword: accounts.member.password,
    ownerEmail: accounts.owner.email, ownerPassword: accounts.owner.password,
    ownerSecret: factor.secret, ownerPeriod: String(factor.period),
    ownerDigits: String(factor.digits), ownerUsedCounter: String(factor.usedCounter)};
  const args = ["shell", "am", "instrument", "-w", "-r"];
  for (const [name, value] of Object.entries(values)) args.push("-e", name, value);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", ["-s", serial, ...args], {encoding: "utf8", timeout: 370_000,
    maxBuffer: 4_000_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter(line =>
      /FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error|Semantics of the node|Node #|Text =/.test(line)).slice(0, 30).join("\n"));
    throw new Error(`Android ${method} failed: ${result.status}`);
  }
  console.log(`Android UI: ${method} passed`);
}

try {
  if ((await list("users")).length) throw new Error("Staging already has users");
  const terms = read(expect(await document("legalDocuments/terms"), 200, "terms").fields.activeVersion);
  const privacy = read(expect(await document("legalDocuments/privacy"), 200, "privacy").fields.activeVersion);
  await signup("member", terms, privacy);
  await signup("owner", terms, privacy);
  const factor = await enrollOwner();
  await create(`organizations/${orgId}`, {id: orgId, name: `Step5 Organization ${suffix}`,
    city: "Wien", shortDescription: "Disposable approved organization",
    moderationStatus: "approved", sourceType: "organization", ownerId: accounts.member.uid,
    adminIds: [], moderatorIds: [], createdAt: new Date(), updatedAt: new Date()});
  await create(`news/${newsId}`, {id: newsId, title: `Step5 nested news ${suffix}`,
    summary: "Disposable content", content: "Disposable content", sourceType: "organization",
    organizationId: orgId, authorId: accounts.member.uid, createdAt: new Date(), updatedAt: new Date()});
  await create(`users/${accounts.member.uid}/newsBookmarks/${newsId}`, {newsId, createdAt: new Date()});
  await setupApp();
  runUi("organizationOwnerCannotDeleteApprovedOrganization", factor);
  const denied = await call(`https://europe-west3-${project}.cloudfunctions.net/deleteOrganization`,
    "POST", {data: {organizationId: orgId}}, accounts.member.idToken);
  if (denied.status !== 403 || (await document(`organizations/${orgId}`)).status !== 200)
    throw new Error(`Organization owner bypassed platform-owner permission: ${denied.status}`);
  try {
    runUi("platformOwnerDeletesApprovedOrganizationWithConfirmation", factor);
  } catch (error) {
    console.error("Deletion failure read-back", JSON.stringify({
      organization: (await document(`organizations/${orgId}`)).status,
      news: (await document(`news/${newsId}`)).status,
      notices: (await list(`users/${accounts.member.uid}/notificationInbox`)).length,
    }));
    throw error;
  }
  if ((await document(`organizations/${orgId}`)).status !== 404 ||
    (await document(`news/${newsId}`)).status !== 404 ||
    (await document(`users/${accounts.member.uid}/newsBookmarks/${newsId}`)).status !== 404)
    throw new Error("Organization content or bookmark survived deletion");
  const notices = await list(`users/${accounts.member.uid}/notificationInbox`);
  if (notices.filter(row => read(row.fields?.sourceId) === orgId).length !== 1)
    throw new Error("Expected exactly one organization deletion notice");
  console.log("Staging step5 approved organization deletion: owner TOTP, role denial, cascade and one notice passed");
} finally {
  if (installed) for (const name of ["at.serlest.ukrainiancommunity.staging.test",
    "at.serlest.ukrainiancommunity.staging"]) adb(["uninstall", name]);
  for (const account of Object.values(accounts)) {
    paths.add(`users/${account.uid}`);
    for (const collection of ["notificationInbox", "newsBookmarks"])
      for (const row of await list(`users/${account.uid}/${collection}`))
        paths.add(`users/${account.uid}/${collection}/${row.name.split("/").at(-1)}`);
  }
  for (const collection of ["organizationDeletionOperations", "organizationCreationProofs"])
    for (const row of await list(collection))
      if (row.name.endsWith(`/${orgId}`)) paths.add(`${collection}/${orgId}`);
  for (const path of [...paths].sort((a, b) => b.length - a.length)) await remove(path);
  for (const account of Object.values(accounts)) {
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST",
      {localId: account.uid}), 200, "delete Auth identity");
    const lookup = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST",
      {localId: [account.uid]}), 200, "Auth cleanup read-back");
    if ((lookup.users ?? []).length) throw new Error("Auth identity survived cleanup");
  }
  if (debugTokenId) {
    const deleted = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (deleted.status !== 0) throw new Error("App Check token cleanup failed");
  }
  if ((await list("users")).length || (await document(`organizations/${orgId}`)).status !== 404 ||
    (await document(`news/${newsId}`)).status !== 404)
    throw new Error("Staging fixtures survived cleanup");
  console.log("Staging step5 organization deletion cleanup verified");
}
