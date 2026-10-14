import {execFileSync, spawnSync} from "node:child_process";
import {randomBytes} from "node:crypto";

const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5582";
const suffix = randomBytes(8).toString("hex");
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = "https://identitytoolkit.googleapis.com";
const bucket = `${project}.firebasestorage.app`;
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
const galleryOrgId = `step5-gallery-${suffix}`;

async function call(url, method = "GET", body, bearer = token) {
  const response = await fetch(url, {method, headers: {
    ...(bearer ? {authorization: `Bearer ${bearer}`, "x-goog-user-project": project} : {}),
    ...(body === undefined ? {} : {"content-type": "application/json"}),
  }, body: body === undefined ? undefined : JSON.stringify(body)});
  return {status: response.status, data: await response.json().catch(() => ({}))};
}
function expect(result, status, label) {
  if (result.status !== status)
    throw new Error(`${label}: HTTP ${result.status} ${result.data.error?.status ?? ""} ${result.data.error?.message ?? ""}`);
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
function read(item) { return item?.stringValue ?? item?.integerValue ?? item?.booleanValue ?? null; }
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
async function signup(which, terms, privacy) {
  const email = `profile-step5-${which}-${suffix}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `${which} signup`);
  accounts[which] = {uid: signup.localId, email, password, idToken: ""};
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: signup.localId, emailVerified: true}), 200, `${which} verification`);
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, `${which} login`);
  accounts[which].idToken = login.idToken;
  await create(`users/${signup.localId}`, {id: signup.localId, email,
    fullName: `Step5 ${which.toUpperCase()} ${suffix}`, displayName: `Step5 ${which.toUpperCase()} ${suffix}`,
    city: "Wien", bio: "", selectedFederalState: "wien", globalRole: "user",
    accountStatus: "active", blockState: "active", requiresMultiFactorAuth: false,
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy, createdAt: new Date()});
}
function adb(args, timeout = 210_000) {
  const result = spawnSync("adb", ["-s", serial, ...args], {cwd: new URL("..", import.meta.url),
    encoding: "utf8", timeout, maxBuffer: 4_000_000});
  if (result.status !== 0) throw new Error(`adb ${args.slice(0, 2).join(" ")} failed: ${result.stderr?.trim()}`);
  return result.stdout;
}
function setupApp() {
  const env = {...process.env, UAC_STAGING_FIREBASE_PROJECT_ID: project,
    UAC_STAGING_FIREBASE_APPLICATION_ID: client.client_info.mobilesdk_app_id,
    UAC_STAGING_FIREBASE_API_KEY: key, UAC_STAGING_FIREBASE_BUCKET: config.project_info.storage_bucket};
  const built = spawnSync("./gradlew", [":app:assembleStagingDebug", ":app:assembleStagingDebugAndroidTest",
    "--no-daemon", "--console=plain"], {cwd: new URL("..", import.meta.url), env,
    encoding: "utf8", maxBuffer: 4_000_000});
  if (built.status !== 0) throw new Error(`Staging build failed: ${built.stdout?.slice(-3_500)} ${built.stderr?.slice(-900)}`);
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
  const name = `UAC Android step5 profile ${suffix}`;
  const added = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
    "--project", project, "--app", appId, "--display-name", name], {encoding: "utf8"});
  if (added.status !== 0) throw new Error(`App Check registration failed: ${added.stderr}`);
  const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  debugTokenId = listed.stdout.match(new RegExp(`UAC Android step5 profile ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1];
  if (!debugTokenId) throw new Error("App Check debug token ID absent");
  adb(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
}
function runUi(method) {
  const values = {class: `at.uac.android.StagingProfileDeletionJourneyTest#${method}`,
    profileSuffix: suffix, aEmail: accounts.a.email, aPassword: accounts.a.password,
    bEmail: accounts.b.email, bPassword: accounts.b.password};
  const args = ["shell", "am", "instrument", "-w", "-r"];
  for (const [name, item] of Object.entries(values)) args.push("-e", name, item);
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
async function storageObject(uid) {
  const path = encodeURIComponent(`profileImages/${uid}/avatar.jpg`);
  return call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${path}`);
}
async function removeStorage(uid) {
  const path = encodeURIComponent(`profileImages/${uid}/avatar.jpg`);
  if ((await storageObject(uid)).status === 200)
    expect(await call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${path}`, "DELETE"),
      204, "delete synthetic avatar");
  if ((await storageObject(uid)).status !== 404) throw new Error("Avatar survived cleanup");
}
async function galleryObjects() {
  const prefix = `organizations/${galleryOrgId}/`;
  const result = expect(await call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o?prefix=${encodeURIComponent(prefix)}`),
    200, "list synthetic gallery objects");
  return result.items ?? [];
}
async function galleryRecords(collection) {
  return (await list(collection)).filter(row => read(row.fields?.organizationId) === galleryOrgId);
}
async function cleanupGallery() {
  for (const object of await galleryObjects())
    expect(await call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(object.name)}`,
      "DELETE"), 204, "delete synthetic gallery object");
  if ((await galleryObjects()).length) throw new Error("Gallery objects survived cleanup");
  for (const row of await list(`organizations/${galleryOrgId}/photos`))
    paths.add(`organizations/${galleryOrgId}/photos/${row.name.split("/").at(-1)}`);
  for (const collection of ["organizationPhotoOperations", "organizationPhotoGarbage",
    "organizationPhotoRetirements"])
    for (const row of await galleryRecords(collection))
      paths.add(`${collection}/${row.name.split("/").at(-1)}`);
  paths.add(`organizations/${galleryOrgId}`);
}

try {
  if ((await list("users")).length !== 0) throw new Error("Staging has existing users");
  for (const collection of ["accountDeletionOperations", "analyticsUserRegistrationEvents",
    "analyticsDeletedUserEvents"])
    if ((await list(collection)).length !== 0) throw new Error(`Staging ${collection} is not empty`);
  const terms = read(expect(await document("legalDocuments/terms"), 200, "Terms").fields.activeVersion);
  const privacy = read(expect(await document("legalDocuments/privacy"), 200, "Privacy").fields.activeVersion);
  await signup("a", terms, privacy);
  await signup("b", terms, privacy);
  setupApp();
  try {
    runUi("avatarAndProfileEditThroughUi");
  } catch (error) {
    const owner = accounts.a.uid;
    const privateState = await document(`users/${owner}`);
    const publicState = await document(`publicProfiles/${owner}`);
    const privateFields = privateState.data.fields ?? {};
    const publicFields = publicState.data.fields ?? {};
    console.error("Avatar failure read-back", JSON.stringify({
      object: (await storageObject(owner)).status,
      private: privateState.status,
      privateAvatar: Boolean(privateFields.avatarURL),
      public: publicState.status,
      publicAvatar: Boolean(publicFields.avatarURL),
      sameAvatar: read(privateFields.avatarURL) === read(publicFields.avatarURL),
      sameName: read(privateFields.displayName) === read(publicFields.displayName),
      sameCity: read(privateFields.city) === read(publicFields.city),
      sameRegion: read(privateFields.selectedFederalState) === read(publicFields.federalState),
      sameId: read(privateFields.id) === read(publicFields.id),
    }));
    throw error;
  }
  const a = accounts.a;
  const privateProfile = expect(await document(`users/${a.uid}`), 200, "private edited profile");
  const publicProfile = expect(await document(`publicProfiles/${a.uid}`), 200, "public edited profile");
  paths.add(`publicProfiles/${a.uid}`);
  const avatarURL = read(privateProfile.fields.avatarURL);
  if (!avatarURL?.includes(encodeURIComponent(`profileImages/${a.uid}/avatar.jpg`)) ||
    read(publicProfile.fields.avatarURL) !== avatarURL ||
    read(privateProfile.fields.bio) !== `Step5 profile ${suffix}` ||
    read(publicProfile.fields.displayName) !== read(privateProfile.fields.displayName))
    throw new Error("Avatar/profile private-public server read-back mismatch");
  const avatar = expect(await storageObject(a.uid), 200, "profile avatar object");
  if (avatar.contentType !== "image/jpeg" || Number(avatar.size) <= 0)
    throw new Error("Avatar storage metadata mismatch");
  const denied = await call(`${base}/users/${a.uid}?updateMask.fieldPaths=avatarURL`, "PATCH",
    {fields: {avatarURL: encode("https://example.invalid/other.jpg")}}, accounts.b.idToken);
  if (denied.status !== 403 ||
    read(expect(await document(`users/${a.uid}`), 200, "unchanged avatar").fields.avatarURL) !== avatarURL)
    throw new Error("Second account modified the first profile");
  runUi("accountSwitchKeepsProfilesSeparate");
  const bBefore = expect(await document(`users/${accounts.b.uid}`), 200, "second profile");
  if (read(bBefore.fields.avatarURL) !== null || read(bBefore.fields.bio) !== "")
    throw new Error("Second account inherited first account data");
  runUi("deleteOwnAccountThroughUi");
  if ((await document(`users/${a.uid}`)).status !== 404 ||
    (await document(`publicProfiles/${a.uid}`)).status !== 404 ||
    (await storageObject(a.uid)).status !== 404)
    throw new Error("Deleted account profile or avatar survived");
  const authA = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST",
    {localId: [a.uid]}), 200, "deleted Auth lookup");
  if ((authA.users ?? []).length) throw new Error("Deleted Auth identity survived");
  const operations = await list("accountDeletionOperations");
  if (operations.length !== 1 || read(operations[0].fields.status) !== "completed")
    throw new Error(`Deletion operation did not complete exactly once: ${JSON.stringify(operations.map(row => ({
      status: read(row.fields.status), stage: read(row.fields.stage),
      suffix: row.name.split("/").at(-1)?.slice(0, 8),
    })) )}`);
  const bAfter = expect(await document(`users/${accounts.b.uid}`), 200, "unaffected second profile");
  if (read(bAfter.fields.displayName) !== read(bBefore.fields.displayName))
    throw new Error("Other account changed during deletion");
  await create(`organizations/${galleryOrgId}`, {id: galleryOrgId,
    name: `Step5 Gallery ${suffix}`, city: "Wien", shortDescription: "Synthetic gallery check",
    moderationStatus: "approved", sourceType: "organization", ownerId: accounts.b.uid,
    adminIds: [], moderatorIds: [], createdAt: new Date(), updatedAt: new Date()});
  runUi("galleryUploadThroughUi");
  const photos = await list(`organizations/${galleryOrgId}/photos`);
  if (photos.length !== 1) throw new Error("Gallery upload metadata absent or duplicated");
  const photoId = photos[0].name.split("/").at(-1);
  paths.add(`organizations/${galleryOrgId}/photos/${photoId}`);
  if (read(photos[0].fields.uploadedBy) !== accounts.b.uid ||
    read(photos[0].fields.caption) !== `Step5 gallery ${suffix}`)
    throw new Error("Gallery upload metadata mismatch");
  const imageURL = read(photos[0].fields.imageURL);
  const imagePath = imageURL && decodeURIComponent(new URL(imageURL).pathname);
  const objectPath = imagePath?.split(`/v0/b/${bucket}/o/`)[1];
  if (!objectPath || !objectPath.startsWith(`organizations/${galleryOrgId}/`) ||
    !objectPath.endsWith(".jpg")) throw new Error("Gallery object path mismatch");
  const galleryObject = expect(await call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(objectPath)}`),
    200, "gallery object after upload");
  if (galleryObject.contentType !== "image/jpeg" || Number(galleryObject.size) <= 0)
    throw new Error("Gallery storage metadata mismatch");
  runUi("galleryRemoveThroughUi");
  if ((await list(`organizations/${galleryOrgId}/photos`)).length)
    throw new Error("Gallery photo metadata survived removal");
  const afterRemoval = await call(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(objectPath)}`);
  if (afterRemoval.status !== 404 && afterRemoval.status !== 200)
    throw new Error(`Gallery object read-back HTTP ${afterRemoval.status}`);
  if (afterRemoval.status === 200 && !(await galleryRecords("organizationPhotoGarbage"))
    .some(row => read(row.fields?.path) === objectPath))
    throw new Error("Gallery object survived without server cleanup job");
  console.log("Staging step5 profile: avatar, edit, account isolation, deletion, gallery upload/remove passed");
  completed = true;
} finally {
  if (installed) for (const packageName of ["at.serlest.ukrainiancommunity.staging.test",
    "at.serlest.ukrainiancommunity.staging"]) adb(["uninstall", packageName]);
  for (const account of Object.values(accounts)) {
    await removeStorage(account.uid);
    paths.add(`publicProfiles/${account.uid}`);
    paths.add(`users/${account.uid}`);
    for (const collection of ["notificationInbox", "notificationPushTokens", "notificationPreferences"])
      for (const row of await list(`users/${account.uid}/${collection}`))
        paths.add(`users/${account.uid}/${collection}/${row.name.split("/").at(-1)}`);
  }
  await cleanupGallery();
  for (const collection of ["accountDeletionOperations", "analyticsUserRegistrationEvents", "analyticsDeletedUserEvents"])
    for (const row of await list(collection)) paths.add(`${collection}/${row.name.split("/").at(-1)}`);
  for (const path of [...paths].sort((a, b) => b.length - a.length)) await remove(path);
  for (const account of Object.values(accounts)) {
    const lookup = expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST",
      {localId: [account.uid]}), 200, "Auth cleanup lookup");
    if ((lookup.users ?? []).length)
      expect(await call(`${authBase}/v1/projects/${project}/accounts:delete`, "POST",
        {localId: account.uid}), 200, "delete synthetic Auth identity");
    if ((expect(await call(`${authBase}/v1/projects/${project}/accounts:lookup`, "POST",
      {localId: [account.uid]}), 200, "Auth cleanup read-back").users ?? []).length)
      throw new Error("Auth identity survived cleanup");
  }
  if (debugTokenId) {
    const deleted = spawnSync("firebase", ["appcheck:debugtokens:delete", debugTokenId,
      "--project", project, "--app", appId, "--force"], {encoding: "utf8"});
    if (deleted.status !== 0) throw new Error("App Check token cleanup failed");
  }
  if ((await list("users")).length !== 0 || (await list("accountDeletionOperations")).length !== 0)
    throw new Error("Staging profile or deletion receipt survived cleanup");
  console.log(`Staging step5 profile cleanup verified${completed ? "" : " after failure"}`);
}
