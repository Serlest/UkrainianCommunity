import {execFileSync, spawnSync} from "node:child_process";
import {randomBytes} from "node:crypto";
import {readdirSync, readFileSync} from "node:fs";

// Exact, disposable staging-only server smoke. This never accepts another project ID.
const project = "uac-android-test-20260903";
const androidUi = process.argv.includes("--android-ui");
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const suffix = randomBytes(8).toString("hex");
const reportId = `dsa-appeal-smoke-${suffix}`;
const caseNumber = `DSA-SMOKE-${suffix}`;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = `https://identitytoolkit.googleapis.com/v1`;
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
  const data = await response.json().catch(() => ({}));
  return {status: response.status, data};
}
function requireStatus(result, status, label) {
  if (result.status !== status) throw new Error(`${label}: HTTP ${result.status}`);
  return result.data;
}
function value(input) {
  if (input === null) return {nullValue: null};
  if (typeof input === "string") return {stringValue: input};
  if (typeof input === "boolean") return {booleanValue: input};
  if (typeof input === "number") return {integerValue: String(input)};
  if (input instanceof Date) return {timestampValue: input.toISOString()};
  if (typeof input === "object") return {mapValue: {fields: fields(input)}};
  throw new Error("Invalid smoke fixture");
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
async function createDocument(path, object) {
  requireStatus(await call(`${base}/${path}`, "PATCH", {fields: fields(object)}), 200, `create ${path}`);
  createdDocuments.push(path);
}
async function getDocument(path) {
  return requireStatus(await call(`${base}/${path}`), 200, `get ${path}`);
}
async function createUser(index, terms, privacy) {
  const email = `dsa-smoke-${suffix}-${index}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signedUp = requireStatus(await call(
    `${authBase}/accounts:signUp?key=${encodeURIComponent(key)}`, "POST",
    {email, password, returnSecureToken: true}, "",
  ), 200, "create Auth user");
  const uid = signedUp.localId;
  if (!uid) throw new Error("No synthetic UID");
  createdUsers.push(uid);
  requireStatus(await call(`${authBase}/projects/${project}/accounts:update`, "POST", {
    localId: uid, emailVerified: true,
  }), 200, "verify synthetic Auth user");
  await createDocument(`users/${uid}`, {
    email, displayName: `DSA smoke ${index}`, accountStatus: "active", blockState: "active",
    globalRole: "user", acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy,
  });
  const login = requireStatus(await call(
    `${authBase}/accounts:signInWithPassword?key=${encodeURIComponent(key)}`, "POST",
    {email, password, returnSecureToken: true}, "",
  ), 200, "sign in verified user");
  return {uid, idToken: login.idToken, email, password};
}
async function invoke(token, payload) {
  return call(`https://europe-west3-${project}.cloudfunctions.net/submitDsaAppeal`,
    "POST", {data: payload}, token);
}
function runAndroidUi(reporter) {
  const client = config.client?.[0];
  const oauthClients = client?.oauth_client ?? [];
  const webClient = oauthClients.find((entry) => entry.client_type === 3)?.client_id;
  const androidClient = oauthClients.find((entry) => entry.client_type === 1 &&
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
    "-Pandroid.testInstrumentationRunnerArguments.class=at.uac.android.StagingDsaAppealJourneyTest",
    `-Pandroid.testInstrumentationRunnerArguments.dsaSmokeEmail=${reporter.email}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaSmokePassword=${reporter.password}`,
    `-Pandroid.testInstrumentationRunnerArguments.dsaSmokeReportId=${reportId}`,
  ], {cwd: new URL("..", import.meta.url), env, encoding: "utf8", maxBuffer: 4_000_000});
  if (result.status !== 0) {
    const safeTail = (result.stdout ?? "").split("\n").filter((line) =>
      /FAILED|Test failed|tests completed|BUILD FAILED|connectedStagingDebugAndroidTest/.test(line)).slice(-8);
    console.error(safeTail.join("\n"));
    throw new Error(`Android staging UI test failed: exit ${result.status}`);
  }
  const root = new URL("../app/build/outputs/androidTest-results/connected/debug/flavors/staging/", import.meta.url);
  const xmlFiles = readdirSync(root, {recursive: true}).filter((name) =>
    String(name).endsWith(".xml") &&
    readFileSync(new URL(String(name), root), "utf8")
      .includes('name="at.uac.android.StagingDsaAppealJourneyTest"'));
  if (xmlFiles.length !== 1) throw new Error("Android staging UI test XML unavailable");
  const xml = readFileSync(new URL(String(xmlFiles[0]), root), "utf8");
  if (!/<testsuite\b[^>]*tests="1"[^>]*failures="0"/.test(xml) ||
      /<skipped\b/.test(xml) || /<failure\b/.test(xml))
    throw new Error("Android staging UI test was skipped or failed");
  console.log("Android staging UI: login, review, submit, confirmed receipt passed (1/1)");
}
const now = new Date();
const updated = new Date(now.getTime() - 60_000);
const deadline = new Date(now.getTime() + 86_400_000);
const reason = "Synthetic staging appeal: the reviewed decision needs another human check.";
let passed = false;
try {
  const [terms, privacy] = await Promise.all([
    getDocument("legalDocuments/terms"), getDocument("legalDocuments/privacy"),
  ]);
  const termsVersion = read(terms.fields?.activeVersion);
  const privacyVersion = read(privacy.fields?.activeVersion);
  if (!termsVersion || !privacyVersion) throw new Error("Current staging legal versions unavailable");
  const reporter = await createUser(1, termsVersion, privacyVersion);
  const outsider = await createUser(2, termsVersion, privacyVersion);
  const decision = {
    outcome: "noAction", factsAndCircumstances: "Synthetic staging facts",
    legalBasis: "Synthetic test basis", termsBasis: null, territorialScope: "AT",
    duration: "Until review", automationUsed: false, humanReviewConfirmed: true,
    actionVerifiedAt: updated, redressInformation: "Appeal available",
    decidedAt: updated, decidedByUserId: "staging-smoke-owner", appealDeadline: deadline,
  };
  const projection = {
    caseNumber, status: "decided", category: "other", exactLocation: "Synthetic location",
    legalBasis: null, illegalExplanation: "Synthetic explanation", evidence: null,
    goodFaithConfirmed: true, acknowledgementAt: updated, preferredLanguage: "de", decision,
  };
  await createDocument(`feedback/${reportId}`, {
    id: reportId, userId: reporter.uid, userDisplayName: "DSA smoke reporter",
    type: "report", subject: "Synthetic staging report", message: "Synthetic staging report",
    status: "closed", createdAt: updated, updatedAt: updated,
    lastMessageText: "Synthetic staging report", lastMessageAt: updated,
    lastMessageByUserId: reporter.uid, lastMessageByRole: "user",
    unreadForOwner: false, unreadForUser: false, dsaCase: projection,
  });
  await createDocument(`dsaCases/${reportId}`, {
    reporterUserId: reporter.uid, caseNumber, status: "decided", decision, updatedAt: updated,
  });
  const revision = `${Math.floor(updated.getTime() / 1000)}:${(updated.getTime() % 1000) * 1_000_000}`;
  const payload = {reportId, reason, operationId: `smoke-${suffix}`, expectedRevision: revision};
  let first;
  if (androidUi) {
    runAndroidUi(reporter);
    const afterUi = await getDocument(`feedback/${reportId}`);
    first = {result: {
      status: read(afterUi.fields?.dsaCase)?.status,
      submittedAt: read(afterUi.fields?.dsaCase)?.appeal?.submittedAt,
      reportId, caseNumber, replayed: false,
    }};
  } else {
    first = requireStatus(await invoke(reporter.idToken, payload), 200, "first appeal");
  }
  if (first.result?.status !== "appealed" || first.result?.replayed !== false ||
      first.result?.reportId !== reportId || first.result?.caseNumber !== caseNumber)
    throw new Error("First appeal receipt mismatch");
  const [feedback, canonical] = await Promise.all([
    getDocument(`feedback/${reportId}`), getDocument(`dsaCases/${reportId}`),
  ]);
  const feedbackCase = read(feedback.fields?.dsaCase);
  const canonicalAppeal = read(canonical.fields?.appeal);
  if (feedbackCase?.status !== "appealed" || feedbackCase?.appeal?.status !== "pending" ||
      feedbackCase?.appeal?.reason !== reason || canonicalAppeal?.reason !== reason ||
      canonicalAppeal?.status !== "pending" ||
      feedbackCase?.appeal?.submittedAt !== first.result.submittedAt)
    throw new Error("Android/iOS projection and canonical case differ");
  if (!androidUi) {
    const replay = requireStatus(await invoke(reporter.idToken, payload), 200, "appeal replay");
    if (replay.result?.replayed !== true || replay.result?.submittedAt !== first.result.submittedAt)
      throw new Error("Idempotency replay mismatch");
  }
  const stale = await invoke(reporter.idToken, {...payload, operationId: `stale-${suffix}`});
  if (stale.status !== 409 || stale.data.error?.status !== "ABORTED")
    throw new Error(`Expected stale-revision rejection; HTTP ${stale.status}`);
  const foreign = await invoke(outsider.idToken, {...payload, operationId: `foreign-${suffix}`});
  if (foreign.status !== 403 || foreign.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Expected foreign-account rejection; HTTP ${foreign.status}`);
  passed = true;
  console.log(`Staging DSA appeal: ${androidUi ? "Android UI" : "direct callable"} commit/read-back, stale revision, foreign account passed${androidUi ? "" : ", replay passed"}`);
} finally {
  // Child messages must go first. All paths are exact UUID-style smoke markers.
  const messages = await call(`${base}/feedback/${reportId}/messages?pageSize=100`);
  for (const document of messages.data.documents ?? []) {
    if (document.name?.startsWith(`projects/${project}/databases/(default)/documents/feedback/${reportId}/messages/`)) {
      requireStatus(await call(`https://firestore.googleapis.com/v1/${document.name}`, "DELETE"),
        200, "delete smoke message");
    }
  }
  for (const path of [...createdDocuments].reverse())
    requireStatus(await call(`${base}/${path}`, "DELETE"), 200, `delete ${path}`);
  for (const uid of createdUsers)
    requireStatus(await call(`${authBase}/projects/${project}/accounts:delete`,
      "POST", {localId: uid}), 200, "delete synthetic Auth user");
  const remainingDocs = await Promise.all(createdDocuments.map((path) => call(`${base}/${path}`)));
  if (remainingDocs.some((result) => result.status !== 404))
    throw new Error("Staging smoke cleanup document read-back failed");
  const remainingMessages = await call(`${base}/feedback/${reportId}/messages?pageSize=100`);
  if (remainingMessages.status !== 200 || (remainingMessages.data.documents ?? []).length !== 0)
    throw new Error("Staging smoke cleanup message read-back failed");
  for (const uid of createdUsers) {
    const result = await call(`${authBase}/projects/${project}/accounts:lookup`,
      "POST", {localId: [uid]});
    if (result.status !== 200 || (result.data.users ?? []).length !== 0)
      throw new Error("Staging smoke cleanup Auth read-back failed");
  }
  console.log(`Staging DSA appeal cleanup: ${createdDocuments.length} documents and ${createdUsers.length} Auth users removed${passed ? "" : " after failure"}`);
}
