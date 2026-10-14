import {execFileSync, spawnSync} from "node:child_process";
import {createHmac, randomBytes} from "node:crypto";
import {readdirSync, readFileSync} from "node:fs";

// Exact, disposable staging-only owner proof. Never accepts a different project.
const project = "uac-android-test-20260903";
const appealOutcome = process.argv.includes("--changed") ? "changed" : "upheld";
const caseOutcome = process.argv.includes("--restricted") ? "restricted" :
  process.argv.includes("--removed") ? "removed" : "noAction";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const suffix = randomBytes(8).toString("hex");
const reportId = `dsa-owner-smoke-${suffix}`;
const caseNumber = `DSA-OWNER-SMOKE-${suffix}`;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const oauth = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", [
  "apps:sdkconfig", "ANDROID", appId, "--project", project,
], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong Firebase project");
const key = config.client?.[0]?.api_key?.[0]?.current_key;
if (!key) throw new Error("Staging API key unavailable");

const createdUsers = [];
const createdDocuments = [];
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
function expect(result, status, label) {
  if (result.status !== status) throw new Error(`${label}: HTTP ${result.status}, ${result.data.error?.status ?? "unknown"}, ${result.data.error?.message ?? JSON.stringify(result.data).slice(0, 350)}`);
  return result.data;
}
function value(input) {
  if (input === null) return {nullValue: null};
  if (typeof input === "string") return {stringValue: input};
  if (typeof input === "boolean") return {booleanValue: input};
  if (input instanceof Date) return {timestampValue: input.toISOString()};
  if (typeof input === "object") return {mapValue: {fields: fields(input)}};
  throw new Error("Invalid fixture");
}
function fields(object) {
  return Object.fromEntries(Object.entries(object).map(([name, input]) => [name, value(input)]));
}
function read(field) {
  if (field?.stringValue !== undefined) return field.stringValue;
  if (field?.booleanValue !== undefined) return field.booleanValue;
  if (field?.timestampValue !== undefined) return field.timestampValue;
  if (field?.mapValue !== undefined) return Object.fromEntries(
    Object.entries(field.mapValue.fields ?? {}).map(([name, child]) => [name, read(child)]));
  return null;
}
async function ownerSmokeNotifications() {
  const result = expect(await call(`${base}:runQuery`, "POST", {structuredQuery: {
    from: [{collectionId: "notificationInbox", allDescendants: true}],
  }}), 200, "query staging owner smoke notifications");
  return result.flatMap((row) => row.document ? [row.document] : []).filter((document) =>
    /^dsa-owner-smoke-[a-f0-9]{16}$/.test(read(document.fields?.sourceId)) &&
    document.name?.includes("/notificationInbox/dsa"));
}
async function priorOwnerSmokePublicProfiles() {
  const result = [];
  let page = "";
  do {
    const url = `${base}/publicProfiles?pageSize=1000${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`;
    const response = expect(await call(url), 200, "list staging public profiles");
    result.push(...(response.documents ?? []).filter((document) =>
      /^DSA owner smoke [12]$/.test(read(document.fields?.displayName)) &&
      read(document.fields?.id) === document.name?.split("/").at(-1)));
    page = response.nextPageToken ?? "";
  } while (page);
  return result;
}
if (process.argv.includes("--cleanup-orphans")) {
  const remnants = await ownerSmokeNotifications();
  for (const document of remnants)
    expect(await call(`https://firestore.googleapis.com/v1/${document.name}`, "DELETE"),
      200, "delete prior owner smoke notification");
  const remaining = await ownerSmokeNotifications();
  if (remaining.length) throw new Error("Prior owner smoke notification cleanup failed");
  const profiles = await priorOwnerSmokePublicProfiles();
  for (const document of profiles) {
    const uid = document.name.split("/").at(-1);
    if ((await call(`${base}/users/${uid}`)).status !== 404)
      throw new Error("Matching public profile still has a user; refusing cleanup");
    expect(await call(`https://firestore.googleapis.com/v1/${document.name}`, "DELETE"),
      200, "delete prior owner smoke public profile");
  }
  if ((await priorOwnerSmokePublicProfiles()).length)
    throw new Error("Prior owner smoke public profile cleanup failed");
  console.log(`Prior owner smoke cleanup: ${remnants.length} notifications, ${profiles.length} public profiles removed, zero remaining`);
  process.exit(0);
}
async function createDocument(path, object) {
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(object)}), 200, `create ${path}`);
  createdDocuments.push(path);
}
async function getDocument(path) {
  return expect(await call(`${base}/${path}`), 200, `get ${path}`);
}
async function createUser(index, role, terms, privacy) {
  const email = `dsa-owner-smoke-${suffix}-${index}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, "create Auth user");
  createdUsers.push(signup.localId);
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: signup.localId, emailVerified: true}), 200, "verify Auth user");
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, "login verified user");
  await createDocument(`users/${signup.localId}`, {
    email, displayName: `DSA owner smoke ${index}`, accountStatus: "active", blockState: "active",
    globalRole: role, requiresMultiFactorAuth: role === "owner",
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy,
  });
  return {uid: signup.localId, idToken: login.idToken, email, password};
}
function base32Decode(input) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0; let count = 0; const bytes = [];
  for (const char of input.replaceAll("=", "").toUpperCase()) {
    const digit = alphabet.indexOf(char);
    if (digit < 0) throw new Error("Invalid TOTP secret encoding");
    bits = (bits << 5) | digit; count += 5;
    if (count >= 8) {count -= 8; bytes.push((bits >> count) & 255);}
  }
  return Buffer.from(bytes);
}
function totp(secret, period, digits, at = Date.now()) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at / 1000 / period)));
  const digest = createHmac("sha1", base32Decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % (10 ** digits)).padStart(digits, "0");
}
async function enrollOwner(owner) {
  const started = expect(await call(`${authBase}/v2/accounts/mfaEnrollment:start?key=${key}`,
    "POST", {idToken: owner.idToken, totpEnrollmentInfo: {}}, ""), 200, "start owner TOTP");
  const info = started.totpSessionInfo;
  if (!info?.sharedSecretKey || !info?.sessionInfo) throw new Error("No TOTP enrollment info");
  // The disposable secret stays only in this process and the instrumentation argument.
  const secret = info.sharedSecretKey;
  const period = info.periodSec ?? 30;
  const digits = info.verificationCodeLength ?? 6;
  expect(await call(`${authBase}/v2/accounts/mfaEnrollment:finalize?key=${key}`, "POST", {
    idToken: owner.idToken, displayName: "Staging owner proof",
    totpVerificationInfo: {sessionInfo: info.sessionInfo, verificationCode: totp(secret, period, digits)},
  }, ""), 200, "enroll owner TOTP");
  const challenged = await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email: owner.email, password: owner.password, returnSecureToken: true}, "");
  if (challenged.status !== 200 || !challenged.data.mfaPendingCredential ||
      !challenged.data.mfaInfo?.[0]?.mfaEnrollmentId || challenged.data.idToken)
    throw new Error(`Owner password login did not require MFA: HTTP ${challenged.status}, ` +
      `error=${challenged.data.error?.message ?? "none"}, ` +
      `fields=${Object.keys(challenged.data).join(",")}, ` +
      `factorFields=${Object.keys(challenged.data.mfaInfo?.[0] ?? {}).join(",")}`);
  const nextWindowMs = (period - (Date.now() / 1_000) % period + 1) * 1_000;
  await new Promise((resolve) => setTimeout(resolve, nextWindowMs));
  const signInAt = Date.now();
  const completed = expect(await call(`${authBase}/v2/accounts/mfaSignIn:finalize?key=${key}`, "POST", {
    mfaPendingCredential: challenged.data.mfaPendingCredential,
    mfaEnrollmentId: challenged.data.mfaInfo[0].mfaEnrollmentId,
    totpVerificationInfo: {verificationCode: totp(secret, period, digits, signInAt)},
  }, ""), 200, "complete owner TOTP");
  const payload = JSON.parse(Buffer.from(completed.idToken.split(".")[1], "base64url").toString());
  if (payload.firebase?.sign_in_second_factor !== "totp") throw new Error("No actual TOTP token claim");
  return {secret, period, digits, usedCounter: Math.floor(signInAt / 1_000 / period), idToken: completed.idToken};
}
function invoke(name, token, payload) {
  return call(`https://europe-west3-${project}.cloudfunctions.net/${name}`,
    "POST", {data: payload}, token);
}
function runAndroidUi(owner, factor, action) {
  const client = config.client?.[0];
  const clients = client?.oauth_client ?? [];
  const webClient = clients.find((entry) => entry.client_type === 3)?.client_id;
  const androidClient = clients.find((entry) => entry.client_type === 1 &&
    entry.android_info?.package_name === "at.serlest.ukrainiancommunity.staging");
  const env = {
    ...process.env,
    UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client?.client_info?.mobilesdk_app_id ?? "",
    UAC_STAGING_FIREBASE_API_KEY: key,
    UAC_STAGING_FIREBASE_BUCKET: config.project_info?.storage_bucket ?? "",
    UAC_STAGING_GOOGLE_WEB_CLIENT_ID: webClient && androidClient ? webClient : "",
  };
  const result = spawnSync("./gradlew", [
    ":app:connectedStagingDebugAndroidTest", "--no-daemon", "--console=plain",
    `-Pandroid.testInstrumentationRunnerArguments.class=at.uac.android.StagingDsaOwnerJourneyTest#ownerDecides${action}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerEmail=${owner.email}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerPassword=${owner.password}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerSecret=${factor.secret}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerPeriod=${factor.period}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerDigits=${factor.digits}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerUsedCounter=${factor.usedCounter}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerReportId=${reportId}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerAppealOutcome=${appealOutcome}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaOwnerCaseOutcome=${caseOutcome}`,
  ], {cwd: new URL("..", import.meta.url), env, encoding: "utf8", maxBuffer: 4_000_000});
  if (result.status !== 0) {
    const safeTail = (result.stdout ?? "").split("\n").filter((line) =>
      /FAILED|Test failed|tests completed|BUILD FAILED|connectedStagingDebugAndroidTest/.test(line)).slice(-8);
    console.error(safeTail.join("\n"));
    throw new Error(`Android staging owner ${action} UI failed: exit ${result.status}`);
  }
  const root = new URL("../app/build/outputs/androidTest-results/connected/debug/flavors/staging/", import.meta.url);
  const xmlFiles = readdirSync(root, {recursive: true}).filter((name) =>
    String(name).endsWith(".xml") && readFileSync(new URL(String(name), root), "utf8")
      .includes('name="at.uac.android.StagingDsaOwnerJourneyTest"'));
  if (xmlFiles.length !== 1) throw new Error("Android staging owner XML unavailable");
  const xml = readFileSync(new URL(String(xmlFiles[0]), root), "utf8");
  if (!/<testsuite\b[^>]*tests="1"[^>]*failures="0"/.test(xml) ||
      /<skipped\b/.test(xml) || /<failure\b/.test(xml))
    throw new Error("Android staging owner UI skipped or failed");
  factor.usedCounter = Math.floor(Date.now() / 1_000 / factor.period);
  console.log(`Android staging owner ${action}: real TOTP login and confirmed UI receipt passed`);
}

const now = new Date();
const submitted = new Date(now.getTime() - 60_000);
let passed = false;
try {
  const [terms, privacy] = await Promise.all([
    getDocument("legalDocuments/terms"), getDocument("legalDocuments/privacy"),
  ]);
  const reporter = await createUser(1, "user", read(terms.fields.activeVersion), read(privacy.fields.activeVersion));
  const owner = await createUser(2, "owner", read(terms.fields.activeVersion), read(privacy.fields.activeVersion));
  const factor = await enrollOwner(owner);
  const projection = {
    caseNumber, status: "submitted", category: "other", exactLocation: "Synthetic location",
    legalBasis: null, illegalExplanation: "Synthetic explanation", evidence: null,
    goodFaithConfirmed: true, acknowledgementAt: submitted, preferredLanguage: "de",
  };
  await createDocument(`feedback/${reportId}`, {
    id: reportId, userId: reporter.uid, userDisplayName: "DSA owner smoke reporter",
    type: "report", subject: "Synthetic staging report", message: "Synthetic staging report",
    status: "open", createdAt: submitted, updatedAt: submitted,
    lastMessageText: "Synthetic staging report", lastMessageAt: submitted,
    lastMessageByUserId: reporter.uid, lastMessageByRole: "user",
    unreadForOwner: true, unreadForUser: false, dsaCase: projection,
  });
  if (caseOutcome !== "noAction") await createDocument(`news/${reportId}`, {
    moderationStatus: "pending", visibilityRestricted: caseOutcome === "restricted",
    isDeleted: caseOutcome === "removed",
  });
  await createDocument(`dsaCases/${reportId}`, {
    reporterUserId: reporter.uid, caseNumber, status: "submitted", updatedAt: submitted,
    targetType: caseOutcome === "noAction" ? "external" : "news", targetId: reportId,
  });
  const revision = `${Math.floor(submitted.getTime() / 1000)}:${(submitted.getTime() % 1000) * 1_000_000}`;
  const decision = {
    reportId, outcome: caseOutcome, factsAndCircumstances: "Synthetic staging facts verified by the owner",
    legalBasis: "Synthetic test basis", termsBasis: null, territorialScope: "Österreich",
    duration: "Until review", redressInformation: "Internal appeal available",
    humanReviewConfirmed: true, operationId: `negative-${suffix}`, expectedRevision: revision,
  };
  const denied = await invoke("decideDsaCase", reporter.idToken, decision);
  if (denied.status !== 403 || denied.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Reporter owner-decision denial failed: HTTP ${denied.status}`);
  runAndroidUi(owner, factor, "Case");
  const [afterCase, canonicalCase] = await Promise.all([
    getDocument(`feedback/${reportId}`), getDocument(`dsaCases/${reportId}`),
  ]);
  if (read(afterCase.fields.dsaCase)?.status !== "decided" ||
      read(canonicalCase.fields.status) !== "decided" ||
      read(afterCase.fields.dsaCase)?.decision?.outcome !== caseOutcome ||
      read(canonicalCase.fields.decision)?.outcome !== caseOutcome)
    throw new Error("Case decision projection/canonical mismatch");
  const stale = await invoke("decideDsaCase", factor.idToken,
    {...decision, operationId: `stale-${suffix}`});
  if (stale.status !== 409 || stale.data.error?.status !== "ABORTED")
    throw new Error(`Stale owner decision not rejected: HTTP ${stale.status}`);
  if (caseOutcome !== "removed" || process.argv.includes("--with-appeal")) {
    const appealRevisionDate = new Date(read(afterCase.fields.updatedAt));
    const appealRevision = `${Math.floor(appealRevisionDate.getTime() / 1000)}:${(appealRevisionDate.getTime() % 1000) * 1_000_000}`;
    const appeal = expect(await invoke("submitDsaAppeal", reporter.idToken, {
      reportId, reason: "Synthetic staging appeal requesting another human review.",
      operationId: `appeal-${suffix}`, expectedRevision: appealRevision,
    }), 200, "submit reporter appeal");
    if (appeal.result?.status !== "appealed") throw new Error("Appeal submission receipt mismatch");
    runAndroidUi(owner, factor, "Appeal");
    const [afterAppeal, canonicalAppeal] = await Promise.all([
      getDocument(`feedback/${reportId}`), getDocument(`dsaCases/${reportId}`),
    ]);
    const projected = read(afterAppeal.fields.dsaCase);
    const canonical = read(canonicalAppeal.fields.appeal);
    const expectedStatus = appealOutcome === "changed" ? "submitted" : "appealDecided";
    if (projected?.status !== expectedStatus || read(canonicalAppeal.fields.status) !== expectedStatus ||
        projected?.appeal?.status !== "decided" ||
        projected?.appeal?.outcome !== appealOutcome || canonical?.status !== "decided" ||
        canonical?.outcome !== appealOutcome || canonical?.decisionReason !== projected?.appeal?.reason ||
        appealOutcome === "changed" && projected.decision !== undefined)
      throw new Error("Appeal decision projection/canonical mismatch");
  }
  passed = true;
  console.log(`Staging DSA owner: ${caseOutcome} case${caseOutcome === "removed" && !process.argv.includes("--with-appeal") ? "" : ` and ${appealOutcome} appeal`} UI, real TOTP, role denial, stale CAS and canonical read-back passed`);
} finally {
  const children = await call(`${base}/feedback/${reportId}/messages?pageSize=100`);
  for (const document of children.data.documents ?? []) {
    if (document.name?.startsWith(`projects/${project}/databases/(default)/documents/feedback/${reportId}/messages/`)) {
      expect(await call(`https://firestore.googleapis.com/v1/${document.name}`, "DELETE"), 200, "delete message");
    }
  }
  for (const path of [...createdDocuments].reverse())
    expect(await call(`${base}/${path}`, "DELETE"), 200, `delete ${path}`);
  for (const uid of createdUsers) {
    const notifications = await call(`${base}/users/${uid}/notificationInbox?pageSize=100`);
    for (const document of notifications.data.documents ?? []) {
      if (document.name?.includes(`/users/${uid}/notificationInbox/dsa`) &&
          read(document.fields?.sourceId) === reportId)
        expect(await call(`https://firestore.googleapis.com/v1/${document.name}`, "DELETE"), 200, "delete notification");
    }
    const remainingNotifications = await call(`${base}/users/${uid}/notificationInbox?pageSize=100`);
    if ((remainingNotifications.data.documents ?? []).some((document) =>
      document.name?.includes(`/users/${uid}/notificationInbox/dsa`) &&
      read(document.fields?.sourceId) === reportId))
      throw new Error("Fixture notification cleanup failed");
    const publicProfile = await call(`${base}/publicProfiles/${uid}`);
    if (publicProfile.status === 200)
      expect(await call(`${base}/publicProfiles/${uid}`, "DELETE"), 200, "delete public profile");
    else if (publicProfile.status !== 404) throw new Error("Public profile cleanup read failed");
    if ((await call(`${base}/publicProfiles/${uid}`)).status !== 404)
      throw new Error("Public profile cleanup read-back failed");
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST", {localId: uid}), 200, "delete Auth user");
  }
  const logs = expect(await call(`${base}:runQuery`, "POST", {structuredQuery: {
    from: [{collectionId: "systemLogs"}],
    where: {fieldFilter: {field: {fieldPath: "targetId"}, op: "EQUAL", value: {stringValue: reportId}}},
  }}), 200, "query smoke logs");
  for (const row of logs) {
    const name = row.document?.name;
    if (name?.startsWith(`projects/${project}/databases/(default)/documents/systemLogs/`))
      expect(await call(`https://firestore.googleapis.com/v1/${name}`, "DELETE"), 200, "delete smoke log");
  }
  const remaining = await Promise.all(createdDocuments.map((path) => call(`${base}/${path}`)));
  if (remaining.some((result) => result.status !== 404)) throw new Error("Fixture document cleanup failed");
  for (const uid of createdUsers) {
    const lookup = await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST", {localId: [uid]});
    if (lookup.status !== 200 || (lookup.data.users ?? []).length !== 0)
      throw new Error("Fixture Auth cleanup failed");
  }
  console.log(`Staging owner cleanup: ${createdDocuments.length} documents, ${createdUsers.length} Auth users removed${passed ? "" : " after failure"}`);
}
