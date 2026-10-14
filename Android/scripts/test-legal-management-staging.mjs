import {execFileSync, spawnSync} from "node:child_process";
import {createHmac, randomBytes} from "node:crypto";

// Destructive fixtures are bounded to this disposable Firebase project.
const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5554";
const suffix = randomBytes(8).toString("hex");
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const oauth = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId,
  "--project", project], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong Firebase project");
const client = config.client?.[0];
const key = client?.api_key?.[0]?.current_key;
if (!key) throw new Error("Staging API key unavailable");
const accounts = [];
const createdIds = new Set();
const originals = new Map();
let installed = false;
let debugTokenId = null;

async function call(url, method = "GET", body, token = oauth) {
  const result = await fetch(url, {method, headers: {
    ...(token ? {authorization: `Bearer ${token}`, "x-goog-user-project": project} : {}),
    ...(body === undefined ? {} : {"content-type": "application/json"}),
  }, body: body === undefined ? undefined : JSON.stringify(body)});
  return {status: result.status, data: await result.json().catch(() => ({}))};
}
function expect(result, status, label) {
  if (result.status !== status)
    throw new Error(`${label}: HTTP ${result.status} ${result.data.error?.status ?? ""} ${result.data.error?.message ?? ""}`);
  return result.data;
}
function read(field) {
  return field?.stringValue ?? field?.booleanValue ?? field?.integerValue ?? field?.timestampValue ?? null;
}
function value(item) {
  if (typeof item === "string") return {stringValue: item};
  if (typeof item === "boolean") return {booleanValue: item};
  if (item instanceof Date) return {timestampValue: item.toISOString()};
  throw new Error("Unexpected fixture field");
}
function fields(input) { return Object.fromEntries(Object.entries(input).map(([k, v]) => [k, value(v)])); }
async function document(path) { return call(`${base}/${path}`); }
async function createDocument(path, object) {
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(object)}), 200, `create ${path}`);
}
async function deleteIfExists(path) {
  const current = await document(path);
  if (current.status === 200) expect(await call(`${base}/${path}`, "DELETE"), 200, `delete ${path}`);
  else if (current.status !== 404) throw new Error(`Read failed for ${path}: ${current.status}`);
  if ((await document(path)).status !== 404) throw new Error(`Cleanup readback failed: ${path}`);
}
async function list(path) {
  const result = await call(`${base}/${path}?pageSize=100`);
  return result.status === 404 ? [] : expect(result, 200, `list ${path}`).documents ?? [];
}
async function user(role, terms, privacy) {
  const email = `legal-step3-${suffix}-${role}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `signup ${role}`);
  const uid = signup.localId;
  createdIds.add(uid);
  accounts.push({uid, email, password, role});
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: uid, emailVerified: true}), 200, `verify ${role}`);
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `login ${role}`);
  await createDocument(`users/${uid}`, {
    email, displayName: `Legal step3 ${role}`, globalRole: role === "owner" ? "owner" : "user",
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
  const started = expect(await call(`${authBase}/v2/accounts/mfaEnrollment:start?key=${key}`,
    "POST", {idToken: owner.idToken, totpEnrollmentInfo: {}}, ""), 200, "start TOTP");
  const info = started.totpSessionInfo;
  if (!info?.sharedSecretKey || !info?.sessionInfo) throw new Error("Missing TOTP enrollment");
  const factor = {secret: info.sharedSecretKey, period: info.periodSec ?? 30,
    digits: info.verificationCodeLength ?? 6, usedCounter: 0};
  expect(await call(`${authBase}/v2/accounts/mfaEnrollment:finalize?key=${key}`, "POST", {
    idToken: owner.idToken, displayName: "Staging legal owner",
    totpVerificationInfo: {sessionInfo: info.sessionInfo,
      verificationCode: totp(factor.secret, factor.period, factor.digits)},
  }, ""), 200, "enroll TOTP");
  const challenged = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`,
    "POST", {email: owner.email, password: owner.password, returnSecureToken: true}, ""), 200,
  "challenge owner");
  if (!challenged.mfaPendingCredential || !challenged.mfaInfo?.[0]?.mfaEnrollmentId || challenged.idToken)
    throw new Error("Owner password login did not require MFA");
  const wait = (factor.period - Date.now() / 1_000 % factor.period + 1) * 1_000;
  await new Promise(resolve => setTimeout(resolve, wait));
  const signInAt = Date.now();
  const completed = expect(await call(`${authBase}/v2/accounts/mfaSignIn:finalize?key=${key}`,
    "POST", {mfaPendingCredential: challenged.mfaPendingCredential,
      mfaEnrollmentId: challenged.mfaInfo[0].mfaEnrollmentId,
      totpVerificationInfo: {verificationCode: totp(factor.secret, factor.period, factor.digits, signInAt)}},
  ""), 200, "complete TOTP");
  const token = JSON.parse(Buffer.from(completed.idToken.split(".")[1], "base64url").toString());
  if (token.firebase?.sign_in_second_factor !== "totp") throw new Error("No real TOTP claim");
  factor.usedCounter = Math.floor(signInAt / 1_000 / factor.period);
  return {factor, idToken: completed.idToken};
}
function invoke(name, token, payload) {
  return call(`https://europe-west3-${project}.cloudfunctions.net/${name}`, "POST", {data: payload}, token);
}
function shell(args, timeout = 160_000) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const result = spawnSync("adb", ["-s", serial, ...args], {cwd: new URL("..", import.meta.url),
      encoding: "utf8", timeout, maxBuffer: 4_000_000});
    if (result.status === 0) return result.stdout;
    if (attempt < 2) spawnSync("sleep", ["2"]);
    else throw new Error(`adb ${args.slice(0, 2).join(" ")} failed: ${result.status} ${result.stderr?.trim()}`);
  }
}
function runUi(method, owner, reader, factor, type) {
  const values = {class: `at.uac.android.StagingLegalManagementJourneyTest#${method}`,
    legalType: type, legalReaderUid: reader.uid,
    legalOwnerEmail: owner.email, legalOwnerPassword: owner.password,
    legalOwnerSecret: factor.secret, legalOwnerPeriod: String(factor.period),
    legalOwnerDigits: String(factor.digits), legalOwnerUsedCounter: String(factor.usedCounter),
    legalReaderEmail: reader.email, legalReaderPassword: reader.password};
  const args = ["shell", "am", "instrument", "-w", "-r"];
  for (const [name, item] of Object.entries(values)) args.push("-e", name, item);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", ["-s", serial, ...args], {encoding: "utf8", timeout: 180_000,
    maxBuffer: 4_000_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter(line =>
      /FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error/.test(line)).slice(0, 14).join("\n"));
    throw new Error(`Android staging ${method} failed: ${result.status}`);
  }
  factor.usedCounter = Math.floor(Date.now() / 1_000 / factor.period);
  console.log(`Android staging UI: ${method} (${type}) passed`);
}
function setupApp() {
  const web = client.oauth_client?.find(entry => entry.client_type === 3)?.client_id;
  const android = client.oauth_client?.find(entry => entry.client_type === 1 &&
    entry.android_info?.package_name === "at.serlest.ukrainiancommunity.staging");
  const env = {...process.env, UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key, UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket,
    UAC_STAGING_GOOGLE_WEB_CLIENT_ID: web && android ? web : ""};
  const build = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
    "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
    encoding: "utf8", maxBuffer: 4_000_000});
  if (build.status !== 0) throw new Error(`Staging APK build failed: ${build.status}\n${build.stdout?.slice(-2000)}`);
  for (const apk of ["app/build/outputs/apk/staging/debug/app-staging-debug.apk",
    "app/build/outputs/apk/androidTest/staging/debug/app-staging-debug-androidTest.apk"]) {
    const output = shell(["install", "-r", apk]);
    if (!output.includes("Success")) throw new Error("Staging APK install failed");
  }
  installed = true;
  shell(["logcat", "-c"]);
  shell(["shell", "am", "start", "-n", "at.serlest.ukrainiancommunity.staging/at.uac.android.MainActivity"]);
  let secret = "";
  for (let attempt = 0; attempt < 20 && !secret; attempt++) {
    secret = shell(["logcat", "-d", "-s", "com.google.firebase.appcheck.debug.internal.DebugAppCheckProvider:D"])
      .match(/Firebase App Check debug token: ([a-f0-9-]{36})/)?.[1] ?? "";
    if (!secret) spawnSync("sleep", ["1"]);
  }
  if (!secret) throw new Error("No staging App Check debug token");
  const name = `UAC Android step3 ${suffix}`;
  const created = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
    "--project", project, "--app", appId, "--display-name", name], {encoding: "utf8"});
  if (created.status !== 0) throw new Error("App Check token registration failed");
  const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  debugTokenId = listed.stdout.match(new RegExp(`UAC Android step3 ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1] ?? null;
  if (!debugTokenId) throw new Error("App Check token id unavailable");
  shell(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
}

let passed = false;
try {
  const users = await list("users");
  if (users.length !== 0) throw new Error("Staging project is not isolated: users exist");
  for (const type of ["terms", "privacy"]) {
    const pointer = expect(await document(`legalDocuments/${type}`), 200, `pointer ${type}`);
    const version = read(pointer.fields.activeVersion);
    const next = `${version.split(".")[0]}.${Number(version.split(".")[1]) + 1}`;
    if ((await document(`legalDocuments/${type}/versions/${next}`)).status !== 404)
      throw new Error(`Staging target version ${type}/${next} already exists`);
    originals.set(type, {pointer, next});
  }
  setupApp();
  for (const type of ["terms", "privacy"]) {
    const terms = read((await document("legalDocuments/terms")).data.fields.activeVersion);
    const privacy = read((await document("legalDocuments/privacy")).data.fields.activeVersion);
    const owner = await user("owner", terms, privacy);
    const reader = await user("reader", terms, privacy);
    const {factor, idToken} = await enrollOwner(owner);
    runUi("readerCannotOpenOwnerLegalManagement", owner, reader, factor, type);
    runUi("ownerSavesLegalDraft", owner, reader, factor, type);
    const {next} = originals.get(type);
    const draft = expect(await document(`legalDocuments/${type}/versions/${next}`), 200, "draft");
    if (read(draft.fields.status) !== "draft" || read(draft.fields.supersedesVersion) !==
      read(originals.get(type).pointer.fields.activeVersion) ||
      !draft.fields.locales.mapValue.fields.de || !draft.fields.locales.mapValue.fields.uk)
      throw new Error("Draft is not iOS-compatible");
    const denied = await call(`${base}/legalDocuments/${type}/versions/${next}`, "PATCH",
      {fields: draft.fields}, reader.idToken);
    if (denied.status !== 403) throw new Error(`Reader legal draft mutation not denied: ${denied.status}`);
    try {
      runUi("ownerRejectsStaleDraftAndPublishes", owner, reader, factor, type);
    } catch (error) {
      const pointerNow = await document(`legalDocuments/${type}`);
      const versionNow = await document(`legalDocuments/${type}/versions/${next}`);
      console.error(`Publication diagnostic: pointer=${read(pointerNow.data.fields?.activeVersion)}, version status=${read(versionNow.data.fields?.status)}`);
      throw error;
    }
    const publishedPointer = expect(await document(`legalDocuments/${type}`), 200, "published pointer");
    const published = expect(await document(`legalDocuments/${type}/versions/${next}`), 200, "published version");
    if (read(publishedPointer.fields.activeVersion) !== next ||
      read(published.fields.status) !== "published" ||
      read(published.fields.contentHash) !== read(draft.fields.contentHash) ||
      read(published.fields.publishedBy) !== owner.uid)
      throw new Error("Published pointer/version readback failed");
    const oldVersion = read(originals.get(type).pointer.fields.activeVersion);
    const oldAcceptance = await invoke("acceptLegalDocument", reader.idToken,
      {documentType: type, version: oldVersion, locale: "de", acceptedFromPlatform: "android"});
    if (oldAcceptance.status !== 400 || oldAcceptance.data.error?.status !== "FAILED_PRECONDITION")
      throw new Error(`Stale legal acceptance not denied: ${oldAcceptance.status}`);
    runUi("readerReacceptsNewLegalVersion", owner, reader, factor, type);
    const readerProfile = expect(await document(`users/${reader.uid}`), 200, "reader profile");
    const acceptedField = type === "terms" ? "acceptedTermsVersion" : "acceptedPrivacyVersion";
    if (read(readerProfile.fields[acceptedField]) !== next) throw new Error("Reader version not updated");
    const logs = await list("legalAcceptanceLogs");
    if (!logs.some(log => read(log.fields.userId) === reader.uid &&
      read(log.fields.documentType) === type && read(log.fields.version) === next &&
      read(log.fields.contentHash) === read(published.fields.contentHash) &&
      read(log.fields.acceptedFromPlatform) === "android"))
      throw new Error("Immutable reacceptance receipt missing or mismatched");
    expect(await invoke("acceptLegalDocument", idToken,
      {documentType: type, version: next, locale: "de", acceptedFromPlatform: "android"}),
    200, "owner reacceptance");
    const evidenceAccounts = expect(await invoke("listLegalEvidenceAccounts", idToken,
      {limit: 50}), 200, "evidence account list");
    if (!(evidenceAccounts.result?.accounts ?? []).some(account => account.userId === reader.uid))
      throw new Error("Reader missing from owner evidence account list");
    runUi("ownerOpensCommonEvidenceList", owner, reader, factor, type);
    console.log(`Staging ${type}: owner UI save/publish, role and stale denial, reacceptance, evidence readback passed`);
    // This is a disposable test project. Restore the exact pointer and remove only this test version.
    await cleanupAccounts();
    expect(await call(`${base}/legalDocuments/${type}`, "PATCH", {fields: originals.get(type).pointer.fields}),
      200, `restore ${type} pointer`);
    await deleteIfExists(`legalDocuments/${type}/versions/${next}`);
    if (read((await document(`legalDocuments/${type}`)).data.fields.activeVersion) !== oldVersion)
      throw new Error(`Pointer restoration failed for ${type}`);
  }
  passed = true;
} finally {
  await cleanupAccounts();
  for (const [type, original] of originals) {
    const current = await document(`legalDocuments/${type}`);
    if (current.status === 200 && read(current.data.fields.activeVersion) !==
      read(original.pointer.fields.activeVersion)) {
      expect(await call(`${base}/legalDocuments/${type}`, "PATCH", {fields: original.pointer.fields}),
        200, `emergency restore ${type}`);
    }
    await deleteIfExists(`legalDocuments/${type}/versions/${original.next}`);
  }
  if (debugTokenId) {
    const removed = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (removed.status !== 0) throw new Error("App Check debug token cleanup failed");
  }
  if (installed) for (const packageName of ["at.serlest.ukrainiancommunity.staging.test",
    "at.serlest.ukrainiancommunity.staging"]) shell(["uninstall", packageName]);
  console.log(`Staging legal cleanup: ${createdIds.size} Auth accounts removed, pointers restored${passed ? "" : " after failure"}`);
}

async function cleanupAccounts() {
  for (const account of accounts.splice(0)) {
    const inbox = await list(`users/${account.uid}/notificationInbox`);
    for (const item of inbox) await deleteIfExists(`users/${account.uid}/notificationInbox/${item.name.split("/").at(-1)}`);
    await deleteIfExists(`publicProfiles/${account.uid}`);
    await deleteIfExists(`users/${account.uid}`);
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST", {localId: account.uid}),
      200, "delete Auth account");
  }
  for (const collection of ["legalAcceptanceLogs", "analyticsConsentReceipts"]) {
    const records = await list(collection);
    for (const item of records) if (createdIds.has(item.fields?.userId?.stringValue))
      await deleteIfExists(`${collection}/${item.name.split("/").at(-1)}`);
  }
}
