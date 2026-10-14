import {execFileSync, spawnSync} from "node:child_process";
import {randomBytes} from "node:crypto";

const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5582";
const suffix = randomBytes(8).toString("hex");
const orgId = `step5-org-${suffix}`;
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
let completed = false;

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
function encode(item) {
  if (item === null) return {nullValue: null};
  if (item instanceof Date) return {timestampValue: item.toISOString()};
  if (typeof item === "string") return {stringValue: item};
  if (typeof item === "number") return {integerValue: String(item)};
  if (typeof item === "boolean") return {booleanValue: item};
  if (Array.isArray(item)) return {arrayValue: {values: item.map(encode)}};
  if (item && typeof item === "object") return {mapValue: {fields: fields(item)}};
  throw new Error("Unsupported fixture value");
}
function fields(row) { return Object.fromEntries(Object.entries(row).map(([name, item]) => [name, encode(item)])); }
function value(item) { return item?.stringValue ?? item?.integerValue ?? item?.booleanValue ?? null; }
function values(item) { return (item?.arrayValue?.values ?? []).map(value); }
async function document(path) { return call(`${base}/${path}`); }
async function list(path) {
  const result = await call(`${base}/${path}?pageSize=100`);
  return result.status === 404 ? [] : expect(result, 200, `list ${path}`).documents ?? [];
}
async function create(path, row) {
  paths.add(path);
  expect(await call(`${base}/${path}`, "PATCH", {fields: fields(row)}), 200, `create ${path}`);
}
async function remove(path) {
  const result = await document(path);
  if (result.status === 200) expect(await call(`${base}/${path}`, "DELETE"), 200, `delete ${path}`);
  else if (result.status !== 404) throw new Error(`Read ${path}: HTTP ${result.status}`);
  if ((await document(path)).status !== 404) throw new Error(`Cleanup read-back failed ${path}`);
}
async function signup(who, terms, privacy) {
  const email = `step5-${who}-${suffix}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const result = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `${who} signup`);
  accounts[who] = {uid: result.localId, email, password};
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: result.localId, emailVerified: true}), 200, `${who} verify`);
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `${who} login`);
  accounts[who].idToken = login.idToken;
  await create(`users/${result.localId}`, {email, displayName: `Step5 ${who} ${suffix}`,
    globalRole: "user", accountStatus: "active", blockState: "active",
    requiresMultiFactorAuth: false, acceptedTermsVersion: terms,
    acceptedPrivacyVersion: privacy, createdAt: new Date()});
  await create(`publicProfiles/${result.localId}`, {userId: result.localId,
    displayName: `Step5 ${who} ${suffix}`, city: "Wien", createdAt: new Date()});
}
function adb(args, timeout = 170_000) {
  const result = spawnSync("adb", ["-s", serial, ...args], {cwd: new URL("..", import.meta.url),
    encoding: "utf8", timeout, maxBuffer: 4_000_000});
  if (result.status !== 0) throw new Error(`adb ${args.slice(0, 2).join(" ")} failed: ${result.stderr?.trim()}`);
  return result.stdout;
}
function uiXml() {
  adb(["shell", "uiautomator", "dump", "/sdcard/uac-step5-window.xml"], 30_000);
  return adb(["shell", "cat", "/sdcard/uac-step5-window.xml"]);
}
function setupApp() {
  const env = {...process.env, UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key, UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket};
  const built = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
    "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
    encoding: "utf8", maxBuffer: 4_000_000});
  if (built.status !== 0) throw new Error(`Staging build failed: ${built.stdout?.slice(-4_000)} ${built.stderr?.slice(-900)}`);
  for (const apk of ["app/build/outputs/apk/staging/debug/app-staging-debug.apk",
    "app/build/outputs/apk/androidTest/staging/debug/app-staging-debug-androidTest.apk"])
    if (!adb(["install", "-r", apk]).includes("Success")) throw new Error(`Install failed: ${apk}`);
  installed = true;
  adb(["shell", "pm", "grant", "at.serlest.ukrainiancommunity.staging", "android.permission.POST_NOTIFICATIONS"]);
  adb(["logcat", "-c"]);
  adb(["shell", "am", "start", "-n", "at.serlest.ukrainiancommunity.staging/at.uac.android.MainActivity"]);
  let secret = "";
  for (let index = 0; index < 20 && !secret; index++) {
    secret = adb(["logcat", "-d", "-s", "com.google.firebase.appcheck.debug.internal.DebugAppCheckProvider:D"])
      .match(/Firebase App Check debug token: ([a-f0-9-]{36})/)?.[1] ?? "";
    if (!secret) spawnSync("sleep", ["1"]);
  }
  if (!secret) throw new Error("App Check debug token absent");
  const name = `UAC Android step5 org push ${suffix}`;
  const added = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
    "--project", project, "--app", appId, "--display-name", name], {encoding: "utf8"});
  if (added.status !== 0) throw new Error(`App Check registration failed: ${added.stderr}`);
  const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  debugTokenId = listed.stdout.match(new RegExp(`UAC Android step5 org push ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1];
  if (!debugTokenId) throw new Error("App Check debug token ID absent");
  adb(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
}
function runUi(method) {
  const args = ["shell", "am", "instrument", "-w", "-r"];
  const values = {class: `at.uac.android.StagingOrganizationPushJourneyTest#${method}`,
    step5Suffix: suffix, memberId: accounts.member.uid,
    ownerEmail: accounts.owner.email, ownerPassword: accounts.owner.password,
    memberEmail: accounts.member.email, memberPassword: accounts.member.password};
  for (const [name, item] of Object.entries(values)) args.push("-e", name, item);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", ["-s", serial, ...args], {encoding: "utf8", timeout: 210_000,
    maxBuffer: 4_000_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter(line =>
      /FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error|Semantics of the node|Node #|Text =/.test(line)).slice(0, 30).join("\n"));
    throw new Error(`Android ${method} failed: ${result.status}`);
  }
  console.log(`Android UI: ${method} passed`);
}
async function callable(name, actor, data) {
  return call(`https://europe-west3-${project}.cloudfunctions.net/${name}`,
    "POST", {data}, actor?.idToken ?? "");
}
async function waitFor(label, predicate, attempts = 35) {
  for (let index = 0; index < attempts; index++) {
    const result = await predicate();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
  throw new Error(`${label} did not appear`);
}

try {
  if ((await list("users")).length !== 0) throw new Error("Staging has existing users");
  const terms = value(expect(await document("legalDocuments/terms"), 200, "Terms").fields.activeVersion);
  const privacy = value(expect(await document("legalDocuments/privacy"), 200, "Privacy").fields.activeVersion);
  for (const who of ["owner", "member", "outsider"]) await signup(who, terms, privacy);
  await create(`organizations/${orgId}`, {id: orgId, name: `Staging organization ${suffix}`,
    city: "Wien", shortDescription: "Synthetic organization for role and push checks",
    moderationStatus: "approved", sourceType: "organization", ownerId: accounts.owner.uid,
    adminIds: [], moderatorIds: [], createdAt: new Date(), updatedAt: new Date()});
  await create(`likes/step5-like-${suffix}`, {userId: accounts.member.uid,
    subscribedOrganizationId: orgId, createdAt: new Date()});
  const roleData = {organizationId: orgId, targetUserId: accounts.member.uid, reason: "Step5 staging journey"};
  const denied = await callable("assignOrganizationModerator", accounts.outsider, roleData);
  if (denied.status !== 403 || denied.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Outsider role change not denied: ${denied.status} ${JSON.stringify(denied.data)}`);
  setupApp();
  runUi("memberEnablesPushThroughUi");
  const preferencePath = `users/${accounts.member.uid}/notificationPreferences/settings`;
  paths.add(preferencePath);
  if (value(expect(await document(preferencePath), 200, "push preference").fields.notificationsEnabled) !== true)
    throw new Error("Push preference server read-back mismatch");
  const pushTokensPath = `users/${accounts.member.uid}/notificationPushTokens`;
  const registration = await waitFor("automatic Android FID registration after UI consent", async () =>
    (await list(pushTokensPath)).find(row => value(row.fields.platform) === "android" &&
      value(row.fields.registrationType) === "fid"), 90);
  paths.add(`${pushTokensPath}/${registration.name.split("/").at(-1)}`);
  await new Promise(resolve => setTimeout(resolve, 5_000));
  adb(["shell", "input", "keyevent", "HOME"]);
  expect(await callable("assignOrganizationModerator", accounts.owner, roleData), 200, "owner assigns moderator");
  const orgAfter = expect(await document(`organizations/${orgId}`), 200, "moderator organization");
  if (!values(orgAfter.fields.moderatorIds).includes(accounts.member.uid) ||
    values(orgAfter.fields.adminIds).includes(accounts.member.uid))
    throw new Error("Moderator role server read-back mismatch");
  const inboxPath = `users/${accounts.member.uid}/notificationInbox`;
  const assigned = await waitFor("assigned role inbox", async () =>
    (await list(inboxPath)).find(row => value(row.fields.type) === "organizationRoleAssigned"));
  if (value(assigned.fields.actionType) !== "openOrganization" ||
    value(assigned.fields.actionTargetId) !== orgId ||
    value(assigned.fields.sourceId) !== orgId)
    throw new Error("Role inbox schema incompatible with iOS/Android");
  const assignedPath = `${inboxPath}/${assigned.name.split("/").at(-1)}`;
  paths.add(assignedPath);
  const receipt = await waitFor("FCM acceptance receipt", async () => {
    const result = await document(`${assignedPath}/privateDelivery/push`);
    return result.status === 200 && value(result.data.fields.status) === "complete" ? result.data : null;
  }, 60);
  const accepted = receipt.fields.targets?.mapValue?.fields ?? {};
  if (!Object.values(accepted).some(item => value(item) === "accepted"))
    throw new Error(`FCM did not accept Android registration: ${value(receipt.fields.lastErrorCode)}`);
  paths.add(`${assignedPath}/privateDelivery/push`);
  const displayed = await waitFor("Android OS role notification", async () => {
    const dump = adb(["shell", "dumpsys", "notification", "--noredact"]);
    return dump.includes("pkg=at.serlest.ukrainiancommunity.staging") &&
      dump.includes("uac_updates") ? true : null;
  }, 25);
  if (!displayed) throw new Error("FCM accepted but Android OS did not display role notification");
  console.log("Android OS notification displayed; FCM receipt accepted");
  adb(["shell", "cmd", "statusbar", "expand-notifications"]);
  const notificationNode = await waitFor("role notification in Android shade", async () => {
    const xml = uiXml();
    return xml.match(/<node\b[^>]*text="(?:Organisationsrolle zugewiesen|Роль в організації призначено|Organization role assigned)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
  }, 12);
  const [, left, top, right, bottom] = notificationNode.map(Number);
  adb(["shell", "input", "tap", String(Math.floor((left + right) / 2)),
    String(Math.floor((top + bottom) / 2))]);
  try {
    await waitFor("organization reached from OS notification tap", async () =>
      uiXml().includes(`Staging organization ${suffix}`), 20);
  } catch (error) {
    const labels = [...uiXml().matchAll(/\btext="([^"]{1,120})"/g)]
      .map(match => match[1]).filter(Boolean).filter(item => !item.includes("@"));
    const activity = adb(["shell", "dumpsys", "activity", "activities"]).split("\n")
      .filter(line => /mResumedActivity|topResumedActivity|at\.uac\.android\.PUSH_TAP/.test(line));
    console.error(`Tap diagnostic labels: ${JSON.stringify(labels.slice(0, 22))}`);
    console.error(`Tap diagnostic activity: ${JSON.stringify(activity.slice(0, 5))}`);
    throw error;
  }
  console.log("Android OS notification tap opened the matching organization");
  try {
    runUi("ownerPromotesAndRemovesMemberThroughUi");
  } catch (error) {
    const state = expect(await document(`organizations/${orgId}`), 200, "role failure read-back");
    console.error(`Role failure server state: admin=${values(state.fields.adminIds).length}, moderator=${values(state.fields.moderatorIds).length}`);
    throw error;
  }
  const afterUi = expect(await document(`organizations/${orgId}`), 200, "removed role organization");
  if (values(afterUi.fields.adminIds).includes(accounts.member.uid) ||
    values(afterUi.fields.moderatorIds).includes(accounts.member.uid))
    throw new Error("Android UI role removal server read-back mismatch");
  runUi("memberOpensRoleInboxDestinationThroughUi");
  runUi("memberDisablesPushThroughUi");
  if (value(expect(await document(preferencePath), 200, "withdrawn push preference").fields.notificationsEnabled) !== false ||
    (await list(pushTokensPath)).length !== 0)
    throw new Error("Push opt-out did not remove registration on server");
  adb(["shell", "pm", "revoke", "at.serlest.ukrainiancommunity.staging", "android.permission.POST_NOTIFICATIONS"]);
  runUi("memberEnablesConsentWithOsPermissionDenied");
  if (value(expect(await document(preferencePath), 200, "denied OS preference").fields.notificationsEnabled) !== true ||
    (await list(pushTokensPath)).length !== 0)
    throw new Error("OS notification denial allowed device registration");
  adb(["shell", "pm", "grant", "at.serlest.ukrainiancommunity.staging", "android.permission.POST_NOTIFICATIONS"]);
  runUi("memberRegistersAfterOsPermissionGranted");
  if ((await list(pushTokensPath)).filter(row => value(row.fields.registrationType) === "fid").length !== 1)
    throw new Error("Permission grant did not register exactly one Android installation");
  runUi("memberDisablesPushThroughUi");
  if ((await list(pushTokensPath)).length !== 0)
    throw new Error("Final push opt-out left a registration");
  const notices = await list(inboxPath);
  if (notices.filter(row => value(row.fields.type) === "organizationRoleAssigned").length < 2 ||
    !notices.some(row => value(row.fields.type) === "organizationRoleRemoved"))
    throw new Error("Role inbox transition history incomplete");
  const audits = (await list("auditLogs")).filter(row =>
    value(row.fields.targetUserId) === accounts.member.uid);
  if (audits.length < 3) throw new Error("Role audit trail incomplete");
  console.log("Staging step5 organization: outsider denied, Android roles and inbox, FCM display/tap, permission gate, opt-out and token cleanup passed");
  completed = true;
} finally {
  for (const account of Object.values(accounts)) {
    for (const collection of ["notificationInbox", "notificationPushTokens", "notificationPreferences"])
      for (const row of await list(`users/${account.uid}/${collection}`)) {
        const childPath = `users/${account.uid}/${collection}/${row.name.split("/").at(-1)}`;
        if (collection === "notificationInbox")
          for (const nested of await list(`${childPath}/privateDelivery`))
            paths.add(`${childPath}/privateDelivery/${nested.name.split("/").at(-1)}`);
        paths.add(childPath);
      }
  }
  for (const row of await list("auditLogs"))
    if (Object.values(accounts).some(account => value(row.fields.targetUserId) === account.uid ||
      value(row.fields.performedBy) === account.uid))
      paths.add(`auditLogs/${row.name.split("/").at(-1)}`);
  for (const path of [...paths].sort((a, b) => b.length - a.length)) await remove(path);
  for (const account of Object.values(accounts)) {
    expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST",
      {localId: account.uid}), 200, "delete Auth account");
    const lookup = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`,
      "POST", {localId: [account.uid]}), 200, "Auth read-back");
    if ((lookup.users ?? []).length) throw new Error("Auth account survived cleanup");
  }
  if (debugTokenId) {
    const deleted = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (deleted.status !== 0) throw new Error("App Check token cleanup failed");
  }
  if (installed) for (const packageName of ["at.serlest.ukrainiancommunity.staging.test",
    "at.serlest.ukrainiancommunity.staging"]) adb(["uninstall", packageName]);
  adb(["shell", "rm", "-f", "/sdcard/uac-step5-window.xml"]);
  if ((await list("users")).length !== 0 || (await list("organizations")).some(row =>
    row.name.endsWith(`/${orgId}`))) throw new Error("Staging users or organization survived cleanup");
  console.log(`Staging step5 organization cleanup verified${completed ? "" : " after failure"}`);
}
