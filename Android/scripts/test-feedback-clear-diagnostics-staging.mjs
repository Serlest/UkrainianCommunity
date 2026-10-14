import {execFileSync, spawnSync} from "node:child_process";
import {createHmac, randomBytes} from "node:crypto";

// Destructive fixtures are restricted to this disposable test project.
const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5580";
const suffix = randomBytes(8).toString("hex");
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const oauth = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId,
  "--project", project], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong staging project");
const client = config.client?.[0];
const key = client?.api_key?.[0]?.current_key;
if (!key) throw new Error("Missing staging key");
const accounts = [];
const paths = new Set();
let debugTokenId = null;
let installed = false;

async function call(url, method = "GET", body, token = oauth, appCheck) {
  const response = await fetch(url, {method, headers: {
    ...(token ? {authorization: `Bearer ${token}`, "x-goog-user-project": project} : {}),
    ...(appCheck ? {"X-Firebase-AppCheck": appCheck} : {}),
    ...(body === undefined ? {} : {"content-type": "application/json"}),
  }, body: body === undefined ? undefined : JSON.stringify(body)});
  return {status: response.status, data: await response.json().catch(() => ({}))};
}
function expect(result, status, label) {
  if (result.status !== status) throw new Error(`${label}: HTTP ${result.status} ${result.data.error?.status ?? ""} ${result.data.error?.message ?? ""}`);
  return result.data;
}
function value(item) {
  if (typeof item === "string") return {stringValue: item};
  if (typeof item === "boolean") return {booleanValue: item};
  if (item instanceof Date) return {timestampValue: item.toISOString()};
  throw new Error("Unexpected fixture value");
}
function fields(input) { return Object.fromEntries(Object.entries(input).map(([k, v]) => [k, value(v)])); }
function read(field) { return field?.stringValue ?? field?.booleanValue ?? field?.integerValue ?? field?.timestampValue ?? null; }
async function document(path) { return call(`${base}/${path}`); }
async function list(path) {
  const result = await call(`${base}/${path}?pageSize=100`);
  return result.status === 404 ? [] : expect(result, 200, `list ${path}`).documents ?? [];
}
async function create(path, object) {
  paths.add(path);
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(object)}), 200, `create ${path}`);
}
async function remove(path) {
  const existing = await document(path);
  if (existing.status === 200) expect(await call(`${base}/${path}`, "DELETE"), 200, `delete ${path}`);
  else if (existing.status !== 404) throw new Error(`Read ${path}: HTTP ${existing.status}`);
  if ((await document(path)).status !== 404) throw new Error(`Cleanup read-back failed ${path}`);
}
async function user(role, terms, privacy) {
  const email = `feedback-step4-${suffix}-${role}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `signup ${role}`);
  const account = {uid: signup.localId, email, password, role, idToken: ""};
  accounts.push(account);
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: account.uid, emailVerified: true}), 200, `verify ${role}`);
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `login ${role}`);
  account.idToken = login.idToken;
  await create(`users/${account.uid}`, {
    email, displayName: `Feedback step4 ${role}`, globalRole: role === "owner" ? "owner" : "user",
    accountStatus: "active", blockState: "active", requiresMultiFactorAuth: role === "owner",
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy, createdAt: new Date(),
  });
  return account;
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
  if (!info?.sharedSecretKey || !info?.sessionInfo) throw new Error("Missing TOTP session");
  const factor = {secret: info.sharedSecretKey, period: info.periodSec ?? 30,
    digits: info.verificationCodeLength ?? 6, usedCounter: 0};
  expect(await call(`${authBase}/v2/accounts/mfaEnrollment:finalize?key=${key}`, "POST", {
    idToken: owner.idToken, displayName: "Staging feedback owner",
    totpVerificationInfo: {sessionInfo: info.sessionInfo,
      verificationCode: totp(factor.secret, factor.period, factor.digits)},
  }, ""), 200, "enroll TOTP");
  const challenge = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`,
    "POST", {email: owner.email, password: owner.password, returnSecureToken: true}, ""), 200,
  "challenge owner");
  if (!challenge.mfaPendingCredential || challenge.idToken) throw new Error("TOTP challenge missing");
  await new Promise(resolve => setTimeout(resolve,
    (factor.period - Date.now() / 1_000 % factor.period + 1) * 1_000));
  const at = Date.now();
  const signed = expect(await call(`${authBase}/v2/accounts/mfaSignIn:finalize?key=${key}`,
    "POST", {mfaPendingCredential: challenge.mfaPendingCredential,
      mfaEnrollmentId: challenge.mfaInfo[0].mfaEnrollmentId,
      totpVerificationInfo: {verificationCode: totp(factor.secret, factor.period, factor.digits, at)}},
  ""), 200, "complete TOTP");
  const claims = JSON.parse(Buffer.from(signed.idToken.split(".")[1], "base64url").toString());
  if (claims.firebase?.sign_in_second_factor !== "totp") throw new Error("TOTP proof absent");
  factor.usedCounter = Math.floor(at / 1_000 / factor.period);
  owner.idToken = signed.idToken;
  return factor;
}
function shell(args, timeout = 160_000) {
  const result = spawnSync("adb", ["-s", serial, ...args], {
    cwd: new URL("..", import.meta.url), encoding: "utf8", timeout, maxBuffer: 4_000_000,
  });
  if (result.status !== 0) throw new Error(`adb ${args.slice(0, 2).join(" ")} failed: ${result.stderr?.trim()}`);
  return result.stdout;
}
function setupApp() {
  const web = client.oauth_client?.find(entry => entry.client_type === 3)?.client_id;
  const android = client.oauth_client?.find(entry => entry.client_type === 1 &&
    entry.android_info?.package_name === "at.serlest.ukrainiancommunity.staging");
  const env = {...process.env, UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key, UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket,
    UAC_STAGING_GOOGLE_WEB_CLIENT_ID: web && android ? web : ""};
  const built = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
    "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
    encoding: "utf8", maxBuffer: 4_000_000});
  if (built.status !== 0) throw new Error(`Staging APK build failed: ${built.stdout?.slice(-2500)}`);
  for (const apk of ["app/build/outputs/apk/staging/debug/app-staging-debug.apk",
    "app/build/outputs/apk/androidTest/staging/debug/app-staging-debug-androidTest.apk"]) {
    if (!shell(["install", "-r", apk]).includes("Success")) throw new Error("APK install failed");
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
  if (!secret) throw new Error("Staging App Check token absent");
  const name = `UAC Android step4 ${suffix}`;
  const registered = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
    "--project", project, "--app", appId, "--display-name", name], {encoding: "utf8"});
  if (registered.status !== 0) throw new Error("App Check token registration failed");
  const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  debugTokenId = listed.stdout.match(new RegExp(`UAC Android step4 ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1] ?? null;
  if (!debugTokenId) throw new Error("App Check token ID absent");
  shell(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
  return secret;
}
function runUi(method, owner, reader, factor) {
  const values = {class: `at.uac.android.StagingFeedbackClearDiagnosticJourneyTest#${method}`,
    feedbackOwnerEmail: owner.email, feedbackOwnerPassword: owner.password,
    feedbackOwnerSecret: factor.secret, feedbackOwnerPeriod: String(factor.period),
    feedbackOwnerDigits: String(factor.digits), feedbackOwnerUsedCounter: String(factor.usedCounter),
    feedbackReaderEmail: reader.email, feedbackReaderPassword: reader.password};
  const args = ["shell", "am", "instrument", "-w", "-r"];
  for (const [name, item] of Object.entries(values)) args.push("-e", name, item);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", ["-s", serial, ...args], {encoding: "utf8", timeout: 190_000,
    maxBuffer: 4_000_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter(line =>
      /FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error|Semantics of the node|Node #|Text =/.test(line)).slice(0, 22).join("\n"));
    throw new Error(`Android ${method} failed: ${result.status}`);
  }
  factor.usedCounter = Math.floor(Date.now() / 1_000 / factor.period);
  console.log(`Android UI: ${method} passed`);
}

let completed = false;
try {
  for (const collection of ["users", "feedback", "dsaCases", "systemLogs", "auditLogs"])
    if ((await list(collection)).length !== 0) throw new Error(`Staging ${collection} is not empty`);
  const terms = read(expect(await document("legalDocuments/terms"), 200, "Terms").fields.activeVersion);
  const privacy = read(expect(await document("legalDocuments/privacy"), 200, "Privacy").fields.activeVersion);
  const owner = await user("owner", terms, privacy);
  const reader = await user("reader", terms, privacy);
  const factor = await enrollOwner(owner);
  const at = new Date(Date.now() - 60_000);
  for (let index = 1; index <= 3; index++) {
    const id = `feedback-step4-${suffix}-${index}`;
    await create(`feedback/${id}`, {
      id, userId: reader.uid, userDisplayName: "Synthetic reader", type: "question",
      message: `Synthetic message ${index}`, status: "open", createdAt: at, updatedAt: at,
      unreadForOwner: true, unreadForUser: false,
    });
    if (index <= 2) await create(`feedback/${id}/messages/m-${index}`, {
      id: `m-${index}`, feedbackId: id, senderId: reader.uid, senderDisplayName: "Synthetic reader",
      senderRole: "user", text: `Synthetic child ${index}`, createdAt: at, isSystem: false,
    });
    if (index === 3) await create(`dsaCases/${id}`, {
      reporterUserId: reader.uid, caseNumber: `STEP4-${suffix}`, status: "submitted", updatedAt: at,
      targetType: "external", targetId: id,
    });
  }
  const invalidClear = await call(`https://europe-west3-${project}.cloudfunctions.net/clearFeedbackInbox`,
    "POST", {data: {}}, reader.idToken);
  if (invalidClear.status !== 403 || invalidClear.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Reader bulk clear not denied: ${invalidClear.status} ${invalidClear.data.error?.status}`);
  const secret = setupApp();
  paths.add(`systemLogDiagnosticRateLimits/${reader.uid}`);
  runUi("readerCannotClearAndWritesMinimalDiagnostic", owner, reader, factor);
  const logs = await list("systemLogs");
  const diagnostic = logs.find(item => read(item.fields.eventType) === "technicalError" &&
    read(item.fields.actorUserId) === reader.uid);
  if (!diagnostic || read(diagnostic.fields.category) !== "diagnostics" ||
    read(diagnostic.fields.summary) !== "Technical failure in Feedback.FEEDBACK_READ" ||
    read(diagnostic.fields.targetType) !== "diagnostics" ||
    Object.keys(diagnostic.fields.metadata?.mapValue?.fields ?? {}).length !== 0 ||
    ["targetId", "targetTitle", "technicalMessage", "organizationId", "organizationName"].some(k => k in diagnostic.fields))
    throw new Error("Diagnostic server read-back contains missing or private fields");
  const diagnosticPath = `systemLogs/${diagnostic.name.split("/").at(-1)}`;
  paths.add(diagnosticPath);
  const foreignRead = await call(`${base}/${diagnosticPath}`, "GET", undefined, reader.idToken);
  if (foreignRead.status !== 403)
    throw new Error(`Ordinary user could read private system log: HTTP ${foreignRead.status}`);
  paths.add(`systemLogDiagnosticRateLimits/${reader.uid}`);
  const exchange = await call(`https://firebaseappcheck.googleapis.com/v1/projects/966536981122/apps/${appId}:exchangeDebugToken?key=${key}`,
    "POST", {debugToken: secret}, "");
  const appCheck = expect(exchange, 200, "exchange App Check debug token").token;
  const anonymousDiagnostic = await call(`https://europe-west3-${project}.cloudfunctions.net/writeClientDiagnostic`,
    "POST", {data: {eventType: "technicalError", severity: "error", targetType: "diagnostics",
      summary: "Synthetic unauthorized diagnostic"}}, "", appCheck);
  if (anonymousDiagnostic.status !== 401 || anonymousDiagnostic.data.error?.status !== "UNAUTHENTICATED")
    throw new Error(`Unauthenticated diagnostic not denied: ${anonymousDiagnostic.status} ${anonymousDiagnostic.data.error?.status}`);
  if ((await list("feedback")).length !== 3) throw new Error("Feedback fixture vanished before owner UI");
  try {
    runUi("ownerClearsOrdinaryFeedbackViaRealScreen", owner, reader, factor);
  } catch (error) {
    const statuses = await Promise.all([1, 2, 3].map(index =>
      document(`feedback/feedback-step4-${suffix}-${index}`).then(result => result.status)));
    console.error(`Owner clear server state: ${statuses.join(",")}`);
    throw error;
  }
  for (let index = 1; index <= 2; index++) {
    const id = `feedback-step4-${suffix}-${index}`;
    if ((await document(`feedback/${id}`)).status !== 404 ||
      (await document(`feedback/${id}/messages/m-${index}`)).status !== 404)
      throw new Error(`Ordinary feedback ${index} or child survived clear`);
  }
  if ((await document(`feedback/feedback-step4-${suffix}-3`)).status !== 200 ||
    (await document(`dsaCases/feedback-step4-${suffix}-3`)).status !== 200)
    throw new Error("Protected DSA case was removed");
  const audit = (await list("auditLogs")).filter(item =>
    read(item.fields.actionType) === "feedbackInboxCleared" && read(item.fields.performedBy) === owner.uid);
  if (audit.length !== 1) throw new Error(`Expected one bulk deletion audit, got ${audit.length}`);
  for (const item of audit) paths.add(`auditLogs/${item.name.split("/").at(-1)}`);
  completed = true;
  console.log("Staging step4: Android clear 2/2, protected DSA retained, role denied, safe diagnostic and unauthenticated denial passed");
} finally {
  const accountIds = new Set(accounts.map(account => account.uid));
  for (const item of await list("systemLogs")) if (accountIds.has(read(item.fields.actorUserId)) &&
    read(item.fields.summary)?.startsWith("Technical failure in Feedback."))
    paths.add(`systemLogs/${item.name.split("/").at(-1)}`);
  for (const item of await list("auditLogs")) if (accountIds.has(read(item.fields.performedBy)) &&
    read(item.fields.actionType) === "feedbackInboxCleared")
    paths.add(`auditLogs/${item.name.split("/").at(-1)}`);
  for (const path of [...paths].sort((a, b) => b.length - a.length)) await remove(path);
  for (const account of accounts) {
    for (const child of await list(`users/${account.uid}/notificationInbox`))
      await remove(`users/${account.uid}/notificationInbox/${child.name.split("/").at(-1)}`);
    await remove(`publicProfiles/${account.uid}`);
    await remove(`users/${account.uid}`);
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST",
      {localId: account.uid}), 200, "delete Auth account");
    const lookup = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`,
      "POST", {localId: [account.uid]}), 200, "Auth read-back");
    if ((lookup.users ?? []).length !== 0) throw new Error("Auth account survived cleanup");
  }
  if (debugTokenId) {
    const deleted = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (deleted.status !== 0) throw new Error("App Check debug token cleanup failed");
  }
  if (installed) for (const packageName of ["at.serlest.ukrainiancommunity.staging.test",
    "at.serlest.ukrainiancommunity.staging"]) shell(["uninstall", packageName]);
  for (const collection of ["users", "feedback", "dsaCases", "systemLogs", "auditLogs"])
    if ((await list(collection)).length !== 0) throw new Error(`Staging cleanup left ${collection}`);
  console.log(`Staging step4 cleanup verified${completed ? "" : " after failure"}`);
}
