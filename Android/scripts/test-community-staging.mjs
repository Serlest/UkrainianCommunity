import {execFileSync, spawnSync} from "node:child_process";
import {randomBytes, randomUUID} from "node:crypto";
import {readFileSync, unlinkSync, writeFileSync} from "node:fs";

const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const serial = process.env.ANDROID_SERIAL || "emulator-5582";
const suffix = randomBytes(8).toString("hex");
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const bucket = `${project}.firebasestorage.app`;
const authBase = "https://identitytoolkit.googleapis.com";
const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const config = JSON.parse(execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId,
  "--project", project], {encoding: "utf8"}));
if (config.project_info?.project_id !== project) throw new Error("Wrong staging project");
const client = config.client?.[0];
const key = client?.api_key?.[0]?.current_key;
if (!key) throw new Error("Missing staging API key");
const paths = new Set();
let account;
let debugTokenId;
let installed = false;
let storageUploaded = false;
let analyticsGateCreated = false;
const analyticsCollections = ["analyticsDailyStats", "analyticsEventReceipts", "analyticsRateLimits",
  "analyticsUserActivity", "analyticsTopContent", "analyticsRegionStats", "analyticsContentStats",
  "analyticsOrganizationStats", "analyticsUserStats", "analyticsRollupState"];
const storagePath = `step5-banner/${suffix}.jpg`;
const ppmPath = `/tmp/uac-step5-${suffix}.ppm`;
const jpegPath = `/tmp/uac-step5-${suffix}.jpg`;

async function uploadSyntheticBanner() {
  writeFileSync(ppmPath, Buffer.concat([Buffer.from("P6\n16 16\n255\n"),
    Buffer.from(Array.from({length: 256}, () => [32, 72, 116]).flat())]));
  const converted = spawnSync("sips", ["-s", "format", "jpeg", ppmPath, "--out", jpegPath],
    {encoding: "utf8"});
  if (converted.status !== 0) throw new Error(`Synthetic JPEG creation failed: ${converted.stderr}`);
  const jpeg = readFileSync(jpegPath);
  const downloadToken = randomUUID();
  const boundary = `uacstep5${suffix}`;
  const metadata = {name: storagePath, contentType: "image/jpeg",
    metadata: {firebaseStorageDownloadTokens: downloadToken}};
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`),
    Buffer.from(`--${boundary}\r\nContent-Type: image/jpeg\r\n\r\n`), jpeg,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const response = await fetch(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=multipart`,
    {method: "POST", headers: {authorization: `Bearer ${token}`, "x-goog-user-project": project,
      "content-type": `multipart/related; boundary=${boundary}`}, body});
  const result = await response.json().catch(() => ({}));
  if (response.status !== 200) throw new Error(`Synthetic banner upload HTTP ${response.status} ${result.error?.message ?? ""}`);
  storageUploaded = true;
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(storagePath)}?alt=media&token=${downloadToken}`;
  const image = await fetch(url);
  if (image.status !== 200 || image.headers.get("content-type")?.split(";")[0] !== "image/jpeg")
    throw new Error(`Synthetic banner download HTTP ${image.status}`);
  return url;
}

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
function adb(args, timeout = 170_000) {
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
  const name = `UAC Android step5 community ${suffix}`;
  const added = spawnSync("firebase", ["appcheck:debugtokens:create", secret,
    "--project", project, "--app", appId, "--display-name", name], {encoding: "utf8"});
  if (added.status !== 0) throw new Error(`App Check registration failed: ${added.stderr}`);
  const listed = spawnSync("firebase", ["appcheck:debugtokens:list", "--project", project,
    "--app", appId], {encoding: "utf8"});
  debugTokenId = listed.stdout.match(new RegExp(`UAC Android step5 community ${suffix}[^\\n]*?debugTokens/([A-Za-z0-9_-]+)`))?.[1];
  if (!debugTokenId) throw new Error("App Check debug token ID absent");
  adb(["shell", "am", "force-stop", "at.serlest.ukrainiancommunity.staging"]);
}
function runUi(method) {
  const values = {class: `at.uac.android.StagingCommunityJourneyTest#${method}`,
    communitySuffix: suffix, communityEmail: account.email, communityPassword: account.password};
  const args = ["shell", "am", "instrument", "-w", "-r"];
  for (const [name, item] of Object.entries(values)) args.push("-e", name, item);
  args.push("at.serlest.ukrainiancommunity.staging.test/androidx.test.runner.AndroidJUnitRunner");
  const result = spawnSync("adb", ["-s", serial, ...args], {encoding: "utf8", timeout: 200_000,
    maxBuffer: 4_000_000});
  if (result.status !== 0 || !/OK \(1 test\)/.test(result.stdout) || /FAILURES!!!/.test(result.stdout)) {
    console.error((result.stdout ?? "").split("\n").filter(line =>
      /COMMUNITY_DIAG|FAILURES|AssertionError|Exception|at at\.uac\.android\.|INSTRUMENTATION_FAILED|Error|Semantics of the node|Node #|Text =/.test(line)).slice(0, 25).join("\n"));
    throw new Error(`Android ${method} failed: ${result.status}`);
  }
  console.log(`Android UI: ${method} passed`);
}
async function waitFor(label, predicate, attempts = 30) {
  for (let index = 0; index < attempts; index++) {
    const result = await predicate();
    if (result?.length) return result;
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
  throw new Error(`${label} did not appear`);
}

let completed = false;
try {
  if ((await list("users")).length !== 0) throw new Error("Staging has existing users");
  for (const collection of ["bannerMeasurementConsentStates", "bannerMeasurementConsentReceipts",
    "bannerMeasurementEventReceipts", "bannerMeasurementDailyShards", "bannerMeasurementRateLimits"])
    if ((await list(collection)).length !== 0) throw new Error(`Staging ${collection} is not empty`);
  if ((await document("analyticsSchemaState/current")).status !== 404)
    throw new Error("Staging analytics schema gate already exists");
  for (const collection of analyticsCollections)
    if ((await list(collection)).length !== 0) throw new Error(`Staging ${collection} is not empty`);
  const terms = read(expect(await document("legalDocuments/terms"), 200, "Terms").fields.activeVersion);
  const privacy = read(expect(await document("legalDocuments/privacy"), 200, "Privacy").fields.activeVersion);
  const email = `community-step5-${suffix}@example.invalid`;
  const password = randomBytes(32).toString("base64url");
  const signup = expect(await call(`${authBase}/v1/accounts:signUp?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, "signup");
  account = {uid: signup.localId, email, password, idToken: ""};
  expect(await call(`${authBase}/v1/projects/${project}/accounts:update`, "POST",
    {localId: account.uid, emailVerified: true}), 200, "verify");
  const login = expect(await call(`${authBase}/v1/accounts:signInWithPassword?key=${key}`, "POST",
    {email, password, returnSecureToken: true}, ""), 200, "login");
  account.idToken = login.idToken;
  await create(`users/${account.uid}`, {email, displayName: `Step5 ${suffix}`, globalRole: "user",
    accountStatus: "active", blockState: "active", requiresMultiFactorAuth: false,
    acceptedTermsVersion: terms, acceptedPrivacyVersion: privacy, createdAt: new Date()});
  const eventId = `community-step5-event-${suffix}`;
  const newsId = `community-step5-news-${suffix}`;
  const now = new Date();
  await create(`events/${eventId}`, {id: eventId, title: `Staging event ${suffix}`,
    summary: "Synthetic event", details: "Synthetic in-app registration check",
    moderationStatus: "approved", cancellationState: "active", requiresRegistration: true,
    participationMode: "inAppRegistration", registeredCount: 0, capacity: 5,
    startDate: new Date(now.getTime() + 7 * 86_400_000), endDate: new Date(now.getTime() + 7 * 86_400_000 + 3_600_000),
    createdAt: now, updatedAt: now, publishedAt: now,
    localizations: {de: {title: `Staging event ${suffix}`, summary: "Synthetic event", details: "Synthetic registration"},
      uk: {title: `Тестова подія ${suffix}`, summary: "Тестова подія", details: "Тестова реєстрація"}}});
  await create(`news/${newsId}`, {id: newsId, title: `Staging news ${suffix}`,
    summary: "Synthetic news", body: "Synthetic comment check", moderationStatus: "approved",
    sourceType: "organization", createdAt: now, updatedAt: now, publishedAt: now,
    localizations: {de: {title: `Staging news ${suffix}`, subtitle: "Synthetic news", body: "Synthetic comment check"},
      uk: {title: `Тестова новина ${suffix}`, subtitle: "Тестова новина", body: "Тестовий коментар"}}});
  const imageURL = await uploadSyntheticBanner();
  const bannerId = `community-step5-banner-${suffix}`;
  await create(`featuredBanners/${bannerId}`, {id: bannerId, createdBy: account.uid,
    title: `Staging banner ${suffix}`, subtitle: "Synthetic measurement",
    localizations: {de: {title: `Staging banner ${suffix}`, subtitle: "Synthetic measurement"},
      uk: {title: `Тестовий банер ${suffix}`, subtitle: "Тестовий показ"}},
    imageURL, isActive: true, actionType: "news", actionTargetID: newsId,
    regionScope: "allAustria", visibleSections: ["home"], displayDurationSeconds: 6,
    priority: 0, createdAt: now, updatedAt: now});
  const outsider = await call(`https://europe-west3-${project}.cloudfunctions.net/registerForEvent`,
    "POST", {data: {eventId}}, "");
  if (outsider.status !== 401 || outsider.data.error?.status !== "UNAUTHENTICATED")
    throw new Error(`Unauthenticated registration not denied: ${outsider.status}`);
  // The UI can create the registration before a later assertion fails. Track it before launch
  // so the fixture is still removed and checked by the failure path.
  const registrationPath = `registrations/event_${eventId}_${account.uid}`;
  paths.add(registrationPath);
  setupApp();
  runUi("registerAndCommentThroughUi");
  const registration = expect(await document(registrationPath), 200, "registration");
  if (read(registration.fields.userId) !== account.uid || read(registration.fields.eventId) !== eventId ||
    read(expect(await document(`events/${eventId}`), 200, "registered event").fields.registeredCount) !== "1")
    throw new Error("Registration server read-back mismatch");
  const operationId = read(registration.fields.counterOperationId);
  if (operationId) paths.add(`eventRegistrationCounterOperations/${operationId}`);
  const comments = await list(`news/${newsId}/comments`);
  const own = comments.filter(item => read(item.fields.authorId) === account.uid);
  if (own.length !== 1 || read(own[0].fields.text) !== `Staging comment ${suffix}` ||
    read(own[0].fields.moderationStatus) !== "approved" ||
    read(own[0].fields.parentType) !== "news" || read(own[0].fields.parentId) !== newsId)
    throw new Error("Comment server read-back mismatch");
  for (const item of own) paths.add(`news/${newsId}/comments/${item.name.split("/").at(-1)}`);
  runUi("cancelRegistrationThroughUi");
  if ((await document(registrationPath)).status !== 404 ||
    read(expect(await document(`events/${eventId}`), 200, "cancelled event").fields.registeredCount) !== "0")
    throw new Error("Cancellation server read-back mismatch");
  runUi("grantAnalyticsConsentThroughUi");
  const consentPath = `analyticsConsentStates/${account.uid}`;
  const consent = expect(await document(consentPath), 200, "analytics consent");
  paths.add(consentPath);
  if (read(consent.fields.enabled) !== true || read(consent.fields.privacyVersion) !== "2026.21" ||
    read(consent.fields.disclosureVersion) !== "2026-08-25.1")
    throw new Error("Analytics grant version/server state mismatch");
  const consentId = read(consent.fields.consentID);
  const receipts = (await list("analyticsConsentReceipts")).filter(row =>
    read(row.fields.userId) === account.uid && read(row.fields.consentID) === consentId);
  if (receipts.length !== 1 || read(receipts[0].fields.enabled) !== true ||
    read(receipts[0].fields.privacyVersion) !== "2026.21")
    throw new Error("Analytics consent receipt mismatch");
  const receiptPath = `analyticsConsentReceipts/${receipts[0].name.split("/").at(-1)}`;
  paths.add(receiptPath);
  const foreignConsent = await call(`https://europe-west3-${project}.cloudfunctions.net/updateAnalyticsConsentV2`,
    "POST", {data: {principalId: "another-account", enabled: false, consentID: consentId,
      locale: "de", appVersion: "1.2", privacyVersion: "2026.21",
      disclosureVersion: "2026-08-25.1"}}, account.idToken);
  if (foreignConsent.status !== 403 || foreignConsent.data.error?.status !== "PERMISSION_DENIED")
    throw new Error(`Foreign consent mutation not denied: ${foreignConsent.status}`);
  await create("analyticsSchemaState/current", {schemaVersion: 2, status: "complete",
    generation: `step5-staging-${suffix}`, cutoverDay: new Date().toISOString().slice(0, 10)});
  analyticsGateCreated = true;
  runUi("trackNewsViewThroughUi");
  const eventReceipts = await waitFor("Android news_view analytics receipt", async () =>
    (await list("analyticsEventReceipts")).filter(row =>
      read(row.fields.eventName) === "news_view" && read(row.fields.contentID) === newsId));
  if (eventReceipts.length !== 1) throw new Error("Android news view was not deduplicated");
  const analyticsDay = read(eventReceipts[0].fields.analyticsDay);
  const daily = expect(await document(`analyticsDailyStats/${analyticsDay}`), 200, "analytics daily stats");
  if (read(daily.fields.metrics?.mapValue?.fields?.newsViews) !== "1" ||
    read(daily.fields.metrics?.mapValue?.fields?.totalViews) !== "1")
    throw new Error("Daily news view aggregate mismatch");
  const detail = (await list(`analyticsContentStats/${analyticsDay}/items`)).filter(row =>
    read(row.fields.contentID) === newsId);
  if (detail.length !== 1 || read(detail[0].fields.metrics?.mapValue?.fields?.views) !== "1")
    throw new Error("iOS-readable analytics content detail mismatch");
  const duplicate = expect(await call(`https://europe-west3-${project}.cloudfunctions.net/trackAnalyticsEvent`,
    "POST", {data: {name: "news_view", parameters: {content_id: newsId}, consentID: consentId,
      occurredAtMilliseconds: Date.now()}}, account.idToken), 200, "duplicate analytics view");
  if (duplicate.result?.tracked !== false ||
    read(expect(await document(`analyticsDailyStats/${analyticsDay}`), 200, "deduped daily stats")
      .fields.metrics?.mapValue?.fields?.newsViews) !== "1")
    throw new Error("Analytics duplicate incremented the iOS aggregate");
  runUi("withdrawAnalyticsConsentThroughUi");
  if (read(expect(await document(consentPath), 200, "withdrawn consent").fields.enabled) !== false ||
    read(expect(await document(receiptPath), 200, "withdrawn receipt").fields.enabled) !== false)
    throw new Error("Analytics withdrawal not durably recorded");
  const withdrawnView = await call(`https://europe-west3-${project}.cloudfunctions.net/trackAnalyticsEvent`,
    "POST", {data: {name: "news_view", parameters: {content_id: newsId}, consentID: consentId,
      occurredAtMilliseconds: Date.now()}}, account.idToken);
  if (withdrawnView.status < 400 || withdrawnView.data.error?.status !== "FAILED_PRECONDITION")
    throw new Error(`Analytics view after withdrawal not denied: ${withdrawnView.status}`);
  runUi("measureBannerImpressionAndClickThroughUi");
  const bannerConsentPath = `bannerMeasurementConsentStates/${account.uid}`;
  const bannerConsent = expect(await document(bannerConsentPath), 200, "banner consent");
  paths.add(bannerConsentPath);
  const bannerConsentId = read(bannerConsent.fields.consentID);
  if (read(bannerConsent.fields.enabled) !== true || read(bannerConsent.fields.privacyVersion) !== "2026.21")
    throw new Error("Banner consent server state mismatch");
  const bannerReceipts = (await list("bannerMeasurementConsentReceipts")).filter(row =>
    read(row.fields.userId) === account.uid && read(row.fields.consentID) === bannerConsentId);
  if (bannerReceipts.length !== 1 || read(bannerReceipts[0].fields.enabled) !== true)
    throw new Error("Banner consent receipt mismatch");
  const bannerReceiptPath = `bannerMeasurementConsentReceipts/${bannerReceipts[0].name.split("/").at(-1)}`;
  paths.add(bannerReceiptPath);
  let shards = [];
  for (let index = 0; index < 25; index++) {
    shards = (await list("bannerMeasurementDailyShards")).filter(row =>
      read(row.fields.bannerID) === bannerId);
    const impressions = shards.reduce((sum, row) => sum + Number(read(row.fields.impressions) ?? 0), 0);
    const clicks = shards.reduce((sum, row) => sum + Number(read(row.fields.clicks) ?? 0), 0);
    if (impressions >= 1 && clicks >= 1) break;
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
  const impressions = shards.reduce((sum, row) => sum + Number(read(row.fields.impressions) ?? 0), 0);
  const clicks = shards.reduce((sum, row) => sum + Number(read(row.fields.clicks) ?? 0), 0);
  if (impressions < 1 || clicks < 1)
    console.error("Shard read-back", JSON.stringify((await list("bannerMeasurementDailyShards")).map(row => ({
      id: row.name.split("/").at(-1), keys: Object.keys(row.fields), impressions: read(row.fields.impressions),
      clicks: read(row.fields.clicks), banner: read(row.fields.bannerID),
    }))));
  if (impressions < 1 || clicks < 1)
    throw new Error(`Banner UI measurements missing: impressions=${impressions} clicks=${clicks}`);
  const probe = {id: randomUUID(), bannerID: bannerId, section: "home", kind: "click",
    occurredAtMilliseconds: Date.now(), consentID: bannerConsentId};
  const endpoint = `https://europe-west3-${project}.cloudfunctions.net/recordBannerMeasurement`;
  const first = expect(await call(endpoint, "POST", {data: probe}, account.idToken), 200, "first banner probe");
  const firstClickTotal = (await list("bannerMeasurementDailyShards"))
    .filter(row => read(row.fields.bannerID) === bannerId)
    .reduce((sum, row) => sum + Number(read(row.fields.clicks) ?? 0), 0);
  const second = expect(await call(endpoint, "POST", {data: probe}, account.idToken), 200, "duplicate banner probe");
  const secondClickTotal = (await list("bannerMeasurementDailyShards"))
    .filter(row => read(row.fields.bannerID) === bannerId)
    .reduce((sum, row) => sum + Number(read(row.fields.clicks) ?? 0), 0);
  if (first.result?.counted !== true || first.result?.duplicate !== false ||
    second.result?.counted !== true || second.result?.duplicate !== true ||
    firstClickTotal !== clicks + 1 || secondClickTotal !== firstClickTotal)
    throw new Error(`Banner measurement deduplication mismatch: ${JSON.stringify({first: first.result, second: second.result})}`);
  runUi("withdrawBannerMeasurementThroughUi");
  if (read(expect(await document(bannerConsentPath), 200, "withdrawn banner consent").fields.enabled) !== false ||
    read(expect(await document(bannerReceiptPath), 200, "withdrawn banner receipt").fields.enabled) !== false)
    throw new Error("Banner consent withdrawal not recorded");
  const afterWithdrawal = await call(endpoint, "POST", {data: {...probe, id: randomUUID()}}, account.idToken);
  if (afterWithdrawal.status < 400 || afterWithdrawal.data.error?.status !== "FAILED_PRECONDITION")
    throw new Error(`Banner measurement after withdrawal not denied: ${afterWithdrawal.status} ${afterWithdrawal.data.error?.status}`);
  console.log("Staging step5 community: registration, comments, analytics and banner consent, UI impression/click, dedupe, withdrawal and denials passed");
  completed = true;
} finally {
  if (analyticsGateCreated) await remove("analyticsSchemaState/current");
  if (account) {
    for (const collection of analyticsCollections)
      for (const row of await list(collection)) {
        const path = `${collection}/${row.name.split("/").at(-1)}`;
        if (collection === "analyticsContentStats")
          for (const child of await list(`${path}/items`))
            paths.add(`${path}/items/${child.name.split("/").at(-1)}`);
        if (collection === "analyticsOrganizationStats")
          for (const child of await list(`${path}/organizations`))
            paths.add(`${path}/organizations/${child.name.split("/").at(-1)}`);
        paths.add(path);
      }
    for (const collection of ["bannerMeasurementConsentReceipts", "bannerMeasurementEventReceipts",
      "bannerMeasurementDailyShards", "bannerMeasurementRateLimits"])
      for (const row of await list(collection))
        paths.add(`${collection}/${row.name.split("/").at(-1)}`);
    paths.add(`bannerMeasurementConsentStates/${account.uid}`);
    for (const row of await list("analyticsConsentReceipts"))
      if (read(row.fields.userId) === account.uid)
        paths.add(`analyticsConsentReceipts/${row.name.split("/").at(-1)}`);
    paths.add(`analyticsConsentStates/${account.uid}`);
    for (const row of await list(`news/community-step5-news-${suffix}/comments`))
      if (read(row.fields.authorId) === account.uid)
        paths.add(`news/community-step5-news-${suffix}/comments/${row.name.split("/").at(-1)}`);
    for (const row of await list("eventRegistrationCounterOperations"))
      if (read(row.fields.userId) === account.uid) paths.add(`eventRegistrationCounterOperations/${row.name.split("/").at(-1)}`);
    for (const row of await list(`users/${account.uid}/notificationInbox`))
      paths.add(`users/${account.uid}/notificationInbox/${row.name.split("/").at(-1)}`);
    await remove(`publicProfiles/${account.uid}`);
  }
  for (const path of [...paths].sort((a, b) => b.length - a.length)) await remove(path);
  if (account) {
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
  for (const collection of ["users", "registrations", "eventRegistrationCounterOperations",
    "analyticsConsentStates", "analyticsConsentReceipts", "bannerMeasurementConsentStates",
    "bannerMeasurementConsentReceipts", "bannerMeasurementEventReceipts",
    "bannerMeasurementDailyShards", "bannerMeasurementRateLimits", ...analyticsCollections])
    if ((await list(collection)).length !== 0) throw new Error(`Staging cleanup left ${collection}`);
  if ((await document("analyticsSchemaState/current")).status !== 404)
    throw new Error("Staging analytics schema gate survived cleanup");
  if (storageUploaded) {
    const deleted = await fetch(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(storagePath)}`,
      {method: "DELETE", headers: {authorization: `Bearer ${token}`, "x-goog-user-project": project}});
    if (deleted.status !== 204) throw new Error(`Synthetic banner storage cleanup HTTP ${deleted.status}`);
    const checked = await fetch(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(storagePath)}`,
      {headers: {authorization: `Bearer ${token}`, "x-goog-user-project": project}});
    if (checked.status !== 404) throw new Error("Synthetic banner storage survived cleanup");
  }
  for (const path of [ppmPath, jpegPath]) try { unlinkSync(path); } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  console.log(`Staging step5 community cleanup verified${completed ? "" : " after failure"}`);
}
