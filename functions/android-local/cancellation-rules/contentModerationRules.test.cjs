"use strict";

// Read the same reviewed boundary before either Firebase SDK. Synthetic claims below are
// Rules fixtures only: this suite is NOT an Android Auth/TOTP enrollment or sign-in proof.
const boundary = require("./boundary.cjs");
const {projectId, host, port} = require("./environment.cjs");
const {after, before, test} = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID, createHash} = require("node:crypto");
const {readFileSync, openSync, writeFileSync, fsyncSync, closeSync, renameSync, lstatSync} = require("node:fs");
const path = require("node:path");
const {tmpdir} = require("node:os");
const {initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, collection, getDocFromServer, getDocsFromServer, setDoc, updateDoc, deleteDoc,
  runTransaction, query, where, documentId, limit, serverTimestamp, setLogLevel} = require("firebase/firestore");

assert.equal(process.env.UAC_A01B_RULES_LOCAL, "1", "Dedicated A01B runner opt-in is mandatory");
const registryPath = path.resolve(process.env.UAC_A01B_REGISTRY_PATH ?? "");
const registryDirectory = path.dirname(registryPath);
assert.equal(path.basename(registryPath), "owned-fixtures.json");
assert.equal(path.dirname(registryDirectory), path.resolve(tmpdir()));
assert.match(path.basename(registryDirectory), /^uac-a01b-rules-[A-Za-z0-9]+$/);
assert.ok(lstatSync(registryDirectory).isDirectory() && !lstatSync(registryDirectory).isSymbolicLink());
setLogLevel("silent"); // Expected Rules denials are asserted by exact code, not raw SDK log messages.

const prefix = `a01b-${randomUUID()}`;
const owned = new Set();
const receiptIds = new Set();
const clients = new Map();
const time = new Date("2026-09-03T06:00:00Z");
const organizationId = `${prefix}-organization`;
const profileSpecs = {
  owner: {globalRole: "owner", totp: true}, admin: {globalRole: "admin", totp: true},
  member: {globalRole: "user"}, legacyTop: {globalRole: "topAdmin"}, legacyModerator: {globalRole: "moderator"},
  orgOwner: {globalRole: "user"}, orgModerator: {globalRole: "user"},
  unverified: {globalRole: "admin", totp: true, verified: false},
  blockedAccount: {globalRole: "admin", totp: true, accountStatus: "blocked"},
  blockedFlag: {globalRole: "admin", totp: true, blockState: "blocked"},
  inactive: {globalRole: "admin", totp: true, accountStatus: "deactivated"},
  ownerNoTotp: {globalRole: "owner"}, adminNoTotp: {globalRole: "admin"},
  unactivatedOwner: {globalRole: "owner", requiresMultiFactorAuth: false},
};
let environment;
let serial = 0;
let submissions = 0;
let assertions = 0;
let cleaned = false;
const uid = (actor) => `${prefix}-${actor}`;
function writeRegistry() {
  const value = JSON.stringify({version: 1, projectId, host, port, prefix, paths: [...owned],
    cleanupComplete: cleaned, syntheticRulesClaimsOnly: true});
  assert.ok(Buffer.byteLength(value) <= 131_072 && owned.size <= 512, "Bounded exact cleanup registry");
  const temporary = `${registryPath}.new`;
  const file = openSync(temporary, "w", 0o600);
  try { writeFileSync(file, value); fsyncSync(file); } finally { closeSync(file); }
  renameSync(temporary, registryPath);
  assert.equal(readFileSync(registryPath, "utf8"), value);
}
function track(value) {
  const parts = value.split("/");
  assert.equal(parts.length, 2, "Only exact top-level synthetic document fixtures");
  assert.ok(["news", "events", "users", "organizations", "systemLogs"].includes(parts[0]));
  if (parts[0] === "systemLogs") assert.ok(receiptIds.has(parts[1]), "Receipt UUID was minted and registered by this process");
  else assert.ok(parts[1].startsWith(`${prefix}-`), "Exact process-owned synthetic fixture prefix");
  if (!owned.has(value)) { owned.add(value); writeRegistry(); }
  return value;
}
function ref(database, value) { assert.ok(owned.has(value), "Register exact path before any SDK operation"); return doc(database, value); }
function item(kind) { assert.ok(["news", "events"].includes(kind)); return track(`${kind}/${prefix}-content-${++serial}`); }
function operation() {
  const id = randomUUID(); receiptIds.add(id); track(`systemLogs/${id}`); return id;
}
function client(actor) {
  if (!clients.has(actor)) {
    const spec = profileSpecs[actor]; assert.ok(spec);
    clients.set(actor, environment.authenticatedContext(uid(actor), {
      email_verified: spec.verified !== false,
      ...(spec.totp ? {firebase: {sign_in_second_factor: "totp"}} : {}),
    }).firestore());
  }
  return clients.get(actor);
}
function fields(value, overrides = {}) {
  const event = value.startsWith("events/");
  return {
    id: value.split("/")[1], title: "Synthetic review title", summary: "Synthetic review summary",
    ...(event ? {details: "Synthetic complete event details", startDate: new Date(time.getTime() + 86_400_000),
      endDate: new Date(time.getTime() + 90_000_000), venue: "Synthetic hall", city: "Vienna", price: 0,
      requiresRegistration: true, registeredCount: 3, registrationState: "notRegistered", isAllDay: false}
      : {body: "Synthetic complete news body"}),
    sourceType: "organization", organizationId, authorId: uid("orgOwner"), regionScope: "austria",
    createdAt: time, updatedAt: time, publishedAt: time, moderationStatus: "pendingReview",
    likeCount: 4, viewCount: 5, commentCount: 6, likeState: "notLiked", visibility: "public",
    imageURL: "https://example.invalid/synthetic.jpg", mediaMetadata: {alternativeText: "Synthetic image"},
    localizations: {de: {title: "Synthetischer Titel", summary: "Synthetische Zusammenfassung",
      [event ? "details" : "body"]: "Vollständiger synthetischer Inhalt"},
    uk: {title: "Вигаданий заголовок", summary: "Вигаданий опис", [event ? "details" : "body"]: "Повний вигаданий зміст"}},
    ...overrides,
  };
}
async function seed(value, data) {
  track(value);
  await environment.withSecurityRulesDisabled(async (context) => setDoc(ref(context.firestore(), value), data));
}
async function externalUpdate(value, patch) {
  // Deliberate synthetic interleaving only. This is the Rules-test SDK context, NOT Admin SDK.
  await environment.withSecurityRulesDisabled(async (context) => updateDoc(ref(context.firestore(), value), patch));
}
async function fresh(value) {
  let result;
  await environment.withSecurityRulesDisabled(async (context) => { result = await getDocFromServer(ref(context.firestore(), value)); });
  return result;
}
async function freshData(value) { return (await fresh(value)).data(); }
async function denied(promise) {
  await assert.rejects(promise, (error) => {
    assert.equal(error?.code, "permission-denied", "Exact Rules denial, not a timeout, unavailable, stale or schema-transport error"); return true;
  }); assertions++;
}

// Small deterministic fixture encoder, NOT the proposed production Kotlin canonical encoder.
// Fixtures use only safe integers/strings/booleans/null/maps/arrays/SDK timestamps.
function canonical(value) {
  if (value === null) return ["null"];
  if (value instanceof Date) return ["timestamp", Math.floor(value.getTime() / 1000), value.getTime() % 1000 * 1_000_000];
  if (value && typeof value === "object" && typeof value.seconds === "number" && typeof value.nanoseconds === "number")
    return ["timestamp", value.seconds, value.nanoseconds];
  if (Array.isArray(value)) return ["array", value.map(canonical)];
  if (typeof value === "object") return ["map", Object.keys(value).sort().map((key) => [key, canonical(value[key])])];
  if (typeof value === "number") assert.ok(Number.isSafeInteger(value));
  assert.ok(["string", "number", "boolean"].includes(typeof value));
  return [typeof value, value];
}
function digest(value, data, preserved = false) {
  const ignored = new Set(["likeCount", "viewCount", "commentCount", ...(value.startsWith("events/") ? ["registeredCount"] : []),
    ...(preserved ? ["moderationStatus", "updatedAt"] : [])]);
  return createHash("sha256").update(JSON.stringify(canonical(Object.fromEntries(Object.entries(data).filter(([key]) => !ignored.has(key)))))).digest("hex");
}
function reviewed(value, data) { return {reviewHash: digest(value, data), preservedHash: digest(value, data, true)}; }
function intent(value, actor, decision, version, id = operation()) {
  assert.ok(["approved", "rejected"].includes(decision));
  return {value, actor, decision, version, id};
}
function receipt(decision, overrides = {}) {
  const event = decision.value.startsWith("events/");
  const approved = decision.decision === "approved";
  const role = profileSpecs[decision.actor].globalRole;
  return {
    id: decision.id, correlationId: decision.id, createdAt: serverTimestamp(), category: "moderation",
    severity: "notice", severityRank: 2, eventType: approved ? "contentApproved" : "contentRejected",
    actorUserId: uid(decision.actor), actorRole: role, targetType: event ? "event" : "newsPost",
    targetId: decision.value.split("/")[1], moduleName: "Moderation",
    operationName: `${approved ? "approve" : "reject"}${event ? "Event" : "NewsPost"}`,
    outcome: decision.decision, summary: `${event ? "Подію" : "Новину"} ${approved ? "схвалено" : "відхилено"}`,
    isReviewed: false, isAppAdminReadable: role !== "owner", retentionPolicy: "moderationDispute",
    metadata: {schemaVersion: "1", clientPath: "androidAtomicModeration", previousStatus: "pendingReview",
      newStatus: decision.decision, reviewHash: decision.version.reviewHash, preservedHash: decision.version.preservedHash},
    ...overrides,
  };
}
class FixtureStale extends Error { constructor() { super("Synthetic reviewed version changed"); this.code = "fixture-stale"; } }
async function execute(database, decision, options = {}) {
  submissions++;
  // This receipt/operation ID is created outside the retried callback.
  const audit = receipt(decision, options.receiptPatch);
  let attempts = 0;
  const result = await runTransaction(database, async (transaction) => {
    const own = await transaction.get(ref(database, `users/${uid(decision.actor)}`));
    const snapshot = await transaction.get(ref(database, decision.value));
    assert.equal(own.get("globalRole"), profileSpecs[decision.actor].globalRole);
    const data = snapshot.data();
    if (!data || data.moderationStatus !== "pendingReview" || digest(decision.value, data) !== decision.version.reviewHash) throw new FixtureStale();
    assert.equal(data.sourceType, "organization"); assert.equal(data.organizationId, organizationId);
    // Test-only barriers force an independently issued concurrent write after the transaction read.
    // Production transaction callbacks must not contain these side effects or test attempt counters.
    attempts++;
    if (options.afterRead) await options.afterRead(attempts);
    transaction.update(ref(database, decision.value), {moderationStatus: decision.decision, updatedAt: serverTimestamp(), ...options.contentPatch});
    transaction.set(ref(database, `systemLogs/${decision.id}`), audit);
    return {id: decision.id};
  }, {maxAttempts: 5});
  return {...result, attempts};
}
async function rawAtomicProbe(database, decision, patches = {}) {
  submissions++;
  // Deliberately no client preflight: prove unchanged Rules block the atomic write itself.
  return runTransaction(database, async (transaction) => {
    transaction.update(ref(database, decision.value), {moderationStatus: decision.decision, updatedAt: serverTimestamp(), ...patches.content});
    transaction.set(ref(database, `systemLogs/${decision.id}`), receipt(decision, patches.receipt));
  }, {maxAttempts: 1});
}
async function lookup(database, id, owner = false) {
  assert.ok(receiptIds.has(id));
  if (owner) return getDocFromServer(ref(database, `systemLogs/${id}`));
  const rows = await getDocsFromServer(query(collection(database, "systemLogs"), where(documentId(), ">=", id), where(documentId(), "<=", id),
    where("isAppAdminReadable", "==", true), limit(1)));
  assert.ok(rows.size <= 1); return rows.docs[0] ?? null;
}
function matchesReceipt(decision, actual) {
  const expected = receipt(decision);
  const immutable = Object.keys(expected).filter((key) => !["createdAt", "isReviewed"].includes(key));
  return immutable.every((key) => JSON.stringify(canonical(actual[key])) === JSON.stringify(canonical(expected[key])))
    && actual.createdAt?.seconds !== undefined;
}
async function inspect(database, decision) {
  // Only server reads. Receipt absence is never translated into another execute call.
  const log = await lookup(database, decision.id, profileSpecs[decision.actor].globalRole === "owner");
  const snapshot = await getDocFromServer(ref(database, decision.value));
  const data = snapshot.data();
  if (!log?.exists()) return data?.moderationStatus === decision.decision ? "OBSERVED_WITHOUT_RECEIPT" : "UNCONFIRMED";
  if (!matchesReceipt(decision, log.data())) return "CONFLICT";
  if (!data) return "CONFIRMED_UNAVAILABLE";
  return data.moderationStatus === decision.decision && digest(decision.value, data, true) === decision.version.preservedHash
    && JSON.stringify(canonical(data.updatedAt)) === JSON.stringify(canonical(log.get("createdAt"))) ? "CONFIRMED_CURRENT" : "CONFIRMED_CHANGED";
}
async function assertUnchanged(decision, before, previousLog = undefined) {
  assert.deepEqual(await freshData(decision.value), before);
  assert.deepEqual(await freshData(`systemLogs/${decision.id}`), previousLog); assertions += 2;
}
function deferred() { let resolve; const promise = new Promise((done) => { resolve = done; }); return {promise, resolve}; }

before(async () => {
  writeRegistry();
  const rules = readFileSync(path.resolve(__dirname, "../../..", "Firebase/firestore.rules"), "utf8");
  console.log(`A01B unchanged Rules SHA256: ${createHash("sha256").update(rules).digest("hex")}`);
  environment = await initializeTestEnvironment({projectId, firestore: {host, port, rules}});
  for (const [actor, spec] of Object.entries(profileSpecs)) {
    await seed(`users/${uid(actor)}`, {id: uid(actor), globalRole: spec.globalRole,
      accountStatus: spec.accountStatus ?? "active", blockState: spec.blockState ?? "active",
      requiresMultiFactorAuth: spec.requiresMultiFactorAuth ?? ["owner", "admin"].includes(spec.globalRole)});
  }
  await seed(`organizations/${organizationId}`, {id: organizationId, name: "Synthetic review organization", ownerId: uid("orgOwner"),
    adminIds: [], moderatorIds: [uid("orgModerator")], moderationStatus: "approved"});
}, {timeout: 25_000});

after(async () => {
  const errors = [];
  if (environment) {
    for (const value of [...owned].reverse()) {
      try {
        await environment.withSecurityRulesDisabled(async (context) => {
          const target = ref(context.firestore(), value); await deleteDoc(target);
          assert.equal((await getDocFromServer(target)).exists(), false, "Exact owned fixture deletion confirmed from server");
        });
      } catch (error) { errors.push(error); }
    }
    try { await environment.cleanup(); } catch (error) { errors.push(error); }
  }
  assert.equal(boundary.snapshot().blockedAttempts, 0, "No outbound or unrelated-service network attempts");
  cleaned = errors.length === 0; writeRegistry();
  console.log(`A01B_MATRIX: scopedAssertions=${assertions}; atomicSubmissions=${submissions}; exactFixtures=${owned.size}; cleanupComplete=${cleaned}; blockedAttempts=0; syntheticRulesTOTPOnly=true`);
  if (errors.length) throw new AggregateError(errors, "Exact A01B cleanup incomplete; all registered paths were attempted. See private temp registry.");
}, {timeout: 90_000});

// Case 1: each complete combined transaction must pass, not two separately allowed writes.
for (const actor of ["owner", "admin"]) for (const kind of ["news", "events"]) for (const desired of ["approved", "rejected"]) {
  test(`1 ${actor} ${kind} ${desired}: atomic CAS plus receipt preserves every unrelated field`, async () => {
    const value = item(kind); const extra = kind === "events" ? {cancellationState: "cancelled", cancelledAt: time,
      cancelledBy: uid("owner"), cancellationReason: "Synthetic existing server cancellation"} : {};
    await seed(value, fields(value, extra)); const before = await freshData(value);
    const decision = intent(value, actor, desired, reviewed(value, before));
    const result = await execute(client(actor), decision); assert.equal(result.id, decision.id);
    const actual = (await getDocFromServer(ref(client(actor), value))).data();
    const log = (await lookup(client(actor), decision.id, actor === "owner")).data();
    assert.deepEqual({...actual, moderationStatus: before.moderationStatus, updatedAt: before.updatedAt}, before);
    assert.equal(actual.moderationStatus, desired); assert.ok(matchesReceipt(decision, log));
    assert.deepEqual(actual.updatedAt, log.createdAt); assert.equal(await inspect(client(actor), decision), "CONFIRMED_CURRENT");
    const pending = await getDocsFromServer(query(collection(client(actor), kind), where("moderationStatus", "==", "pendingReview"),
      where(documentId(), "==", value.split("/")[1]), limit(1)));
    assert.equal(pending.empty, true); assertions += 7;
  }, {timeout: 15_000});
}

// Case 2: forced raw writes cannot use organization roles or synthetic READY labels as platform authority.
for (const actor of ["guest", "member", "legacyTop", "legacyModerator", "orgOwner", "orgModerator", "unverified",
  "blockedAccount", "blockedFlag", "inactive", "ownerNoTotp", "adminNoTotp"]) {
  test(`2 ${actor}: both content and audit remain unchanged after exact Rules denial`, async () => {
    for (const kind of ["news", "events"]) {
      const value = item(kind); await seed(value, fields(value)); const before = await freshData(value);
      const decision = intent(value, actor === "guest" ? "admin" : actor, "approved", reviewed(value, before));
      const database = actor === "guest" ? environment.unauthenticatedContext().firestore() : client(actor);
      await denied(rawAtomicProbe(database, decision)); await assertUnchanged(decision, before);
    }
  }, {timeout: 15_000});
}

// Case 3: any denied audit field rolls back the otherwise permitted content decision.
const invalidReceipts = {
  actor: () => ({actorUserId: uid("member")}), role: () => ({actorRole: "owner", isAppAdminReadable: false}),
  timestamp: () => ({createdAt: time}), visibility: () => ({isAppAdminReadable: false}), unknownField: () => ({unrecognized: true}),
  eventType: () => ({eventType: "notAnAllowedEvent"}), outcome: () => ({outcome: "notAnAllowedOutcome"}),
  rankType: () => ({severityRank: "2"}), id: () => ({id: "not-the-receipt-document"}),
  acknowledgementOnCreate: () => ({isReviewed: true, reviewedAt: serverTimestamp(), reviewedByUserId: uid("admin")}),
};
for (const [label, patch] of Object.entries(invalidReceipts)) {
  test(`3 invalid receipt ${label}: whole transaction is denied`, async () => {
    const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
    const decision = intent(value, "admin", "approved", reviewed(value, before));
    await denied(execute(client("admin"), decision, {receiptPatch: patch()})); await assertUnchanged(decision, before);
  }, {timeout: 15_000});
}
test("3 event cancellation tampering is denied together with its otherwise valid audit", async () => {
  const value = item("events"); await seed(value, fields(value, {cancellationState: "cancelled", cancelledAt: time,
    cancelledBy: uid("owner"), cancellationReason: "Original synthetic cancellation"}));
  const before = await freshData(value); const decision = intent(value, "owner", "approved", reviewed(value, before));
  await denied(execute(client("owner"), decision, {contentPatch: {cancellationReason: "Changed cancellation"}}));
  await assertUnchanged(decision, before);
});
test("3 trust boundary: Rules permit a separate log and do not bind eventType/outcome to content", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "approved", reviewed(value, before));
  await setDoc(ref(client("admin"), `systemLogs/${decision.id}`), receipt(decision, {outcome: "rejected"}));
  assert.deepEqual(await freshData(value), before, "Standalone privileged log did not imply a content mutation");
  assert.equal(matchesReceipt(decision, await freshData(`systemLogs/${decision.id}`)), false, "Exact client receipt validator rejects semantic mismatch");
  assert.equal(await inspect(client("admin"), decision), "CONFLICT"); assertions += 3;
});

// Case 4: set(existing UUID) cannot overwrite immutable receipt fields or silently duplicate a decision.
for (const reviewedAlready of [false, true]) {
  test(`4 existing ${reviewedAlready ? "reviewed" : "unreviewed"} receipt collision aborts content`, async () => {
    const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
    const decision = intent(value, "admin", "approved", reviewed(value, before));
    const logPath = `systemLogs/${decision.id}`;
    await setDoc(ref(client("admin"), logPath), receipt(decision));
    if (reviewedAlready) await updateDoc(ref(client("admin"), logPath), {isReviewed: true,
      reviewedAt: serverTimestamp(), reviewedByUserId: uid("admin")});
    const logBefore = await freshData(logPath);
    await denied(execute(client("admin"), decision)); await assertUnchanged(decision, before, logBefore);
  });
}
test("4 legitimate acknowledgement preserves receipt evidence; metadata rewrite and delete are denied", async () => {
  const value = item("events"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "rejected", reviewed(value, before)); await execute(client("admin"), decision);
  const target = ref(client("admin"), `systemLogs/${decision.id}`); const original = await freshData(`systemLogs/${decision.id}`);
  await updateDoc(target, {isReviewed: true, reviewedAt: serverTimestamp(), reviewedByUserId: uid("admin")});
  const acknowledged = await freshData(`systemLogs/${decision.id}`);
  const core = {...acknowledged}; delete core.reviewedAt; delete core.reviewedByUserId; core.isReviewed = false;
  assert.deepEqual(core, original); assert.equal(await inspect(client("admin"), decision), "CONFIRMED_CURRENT");
  await denied(updateDoc(target, {metadata: {...acknowledged.metadata, newStatus: "approved"}}));
  await denied(updateDoc(target, {targetId: "other-content"})); await denied(deleteDoc(target));
  await denied(deleteDoc(ref(client("owner"), `systemLogs/${decision.id}`)));
  assert.deepEqual(await freshData(`systemLogs/${decision.id}`), acknowledged); assertions += 3;
});

// Case 5: the proposed narrow query is verified with empty and unreadable results under current Rules.
test("5 admin exact closed-range query works for present and missing; direct/equality missing lookups deny", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "approved", reviewed(value, before)); await execute(client("admin"), decision);
  assert.equal((await lookup(client("admin"), decision.id)).id, decision.id);
  const missing = operation(); assert.equal(await lookup(client("admin"), missing), null);
  await denied(getDocFromServer(ref(client("admin"), `systemLogs/${missing}`)));
  await denied(getDocsFromServer(query(collection(client("admin"), "systemLogs"), where(documentId(), "==", missing),
    where("isAppAdminReadable", "==", true), limit(1))));
  assert.equal((await lookup(client("owner"), decision.id, true)).exists(), true);
  assert.equal((await lookup(client("owner"), missing, true)).exists(), false); assertions += 4;
});
test("5 admin filtered empty result cannot prove an owner receipt is absent", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "owner", "approved", reviewed(value, before)); await execute(client("owner"), decision);
  assert.equal(await lookup(client("admin"), decision.id), null);
  await denied(getDocFromServer(ref(client("admin"), `systemLogs/${decision.id}`)));
  await denied(getDocsFromServer(query(collection(client("admin"), "systemLogs"), where(documentId(), "==", decision.id),
    where("isAppAdminReadable", "==", true), limit(1))));
  assert.equal((await lookup(client("owner"), decision.id, true)).exists(), true); assertions += 2;
});

// Case 6: controlled concurrent writes demonstrate SDK document-version CAS and reread semantics.
const edits = {
  body: (kind) => ({[kind === "news" ? "body" : "details"]: "A different complete synthetic body"}),
  localization: () => ({"localizations.de.title": "Ein anderer Titel"}),
  schedule: () => ({scheduledAt: new Date(time.getTime() + 3_600_000)}),
  media: () => ({imageURL: "https://example.invalid/changed.jpg"}),
  unknownField: () => ({futureReviewMeaning: {enabled: true}}),
  updatedAt: () => ({updatedAt: new Date(time.getTime() + 1000)}),
};
for (const kind of ["news", "events"]) for (const [label, patch] of Object.entries(edits)) {
  test(`6 ${kind} concurrent ${label}: reviewed CAS rejects reread and writes no receipt`, async () => {
    const value = item(kind); await seed(value, fields(value)); const before = await freshData(value);
    const decision = intent(value, "admin", "approved", reviewed(value, before));
    const reached = deferred(); const resume = deferred();
    const transaction = execute(client("admin"), decision, {afterRead: async (attempt) => {
      if (attempt === 1) { reached.resolve(); await resume.promise; }
    }});
    // Attach the handler immediately so an assertion failure cannot cause an unhandled SDK rejection.
    const settled = transaction.then((result) => ({result}), (error) => ({error}));
    await reached.promise;
    let external;
    try { await externalUpdate(value, patch(kind)); external = await freshData(value); }
    finally { resume.resolve(); }
    const result = await settled;
    assert.equal(result.error?.code, "fixture-stale");
    assert.deepEqual(await freshData(value), external); assert.equal((await fresh(`systemLogs/${decision.id}`)).exists(), false); assertions += 3;
  }, {timeout: 20_000});
}
for (const kind of ["news", "events"]) {
  test(`6 ${kind} counter-only interleaving retries safely and preserves all new counts`, async () => {
    const value = item(kind); await seed(value, fields(value)); const before = await freshData(value);
    const decision = intent(value, "admin", "approved", reviewed(value, before));
    const reached = deferred(); const resume = deferred();
    const transaction = execute(client("admin"), decision, {afterRead: async (attempt) => {
      if (attempt === 1) { reached.resolve(); await resume.promise; }
    }});
    const settled = transaction.then((result) => ({result}), (error) => ({error}));
    await reached.promise;
    const counts = {likeCount: 40, viewCount: 50, commentCount: 60, ...(kind === "events" ? {registeredCount: 30} : {})};
    try { await externalUpdate(value, counts); } finally { resume.resolve(); }
    const result = await settled; assert.equal(result.error, undefined); assert.ok(result.result.attempts >= 2);
    const actual = await freshData(value);
    for (const [key, value] of Object.entries(counts)) assert.equal(actual[key], value);
    assert.equal(await inspect(client("admin"), decision), "CONFIRMED_CURRENT"); assertions += 3 + Object.keys(counts).length;
  }, {timeout: 20_000});
}
test("6 simultaneous opposite decisions yield one commit/receipt and one stale loser", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const first = intent(value, "owner", "approved", reviewed(value, before));
  const second = intent(value, "admin", "rejected", reviewed(value, before));
  const reached = deferred(); const resume = deferred(); let arrivals = 0;
  const afterRead = async (attempt) => { if (attempt === 1) { if (++arrivals === 2) reached.resolve(); await resume.promise; } };
  const promises = [execute(client("owner"), first, {afterRead}), execute(client("admin"), second, {afterRead})];
  const settled = Promise.allSettled(promises); await reached.promise; resume.resolve();
  const results = await settled; assert.equal(results.filter((it) => it.status === "fulfilled").length, 1);
  assert.equal(results.find((it) => it.status === "rejected").reason.code, "fixture-stale");
  const winner = results[0].status === "fulfilled" ? first : second;
  const loser = winner === first ? second : first;
  assert.equal((await fresh(`systemLogs/${winner.id}`)).exists(), true);
  assert.equal((await fresh(`systemLogs/${loser.id}`)).exists(), false);
  assert.equal((await freshData(value)).moderationStatus, winner.decision); assertions += 5;
}, {timeout: 20_000});

// Case 7: old clients still work, but observed postconditions never identify an unknown writer.
test("7 old-client two-field decision is compatible; missing receipt stays observed-only on repeated reads", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "approved", reviewed(value, before));
  await updateDoc(ref(client("admin"), value), {moderationStatus: "approved", updatedAt: serverTimestamp()});
  const count = submissions;
  assert.equal(await inspect(client("admin"), decision), "OBSERVED_WITHOUT_RECEIPT");
  assert.equal(await inspect(client("admin"), decision), "OBSERVED_WITHOUT_RECEIPT");
  assert.equal(submissions, count); assert.equal((await fresh(`systemLogs/${decision.id}`)).exists(), false); assertions += 4;
});
test("7 deliberately discarded ACK recovers from receipt; later old-client decision is reported as changed", async () => {
  const value = item("events"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "approved", reviewed(value, before)); await execute(client("admin"), decision);
  const count = submissions; // ACK is intentionally ignored here; this is not a network fault-injection claim.
  assert.equal(await inspect(client("admin"), decision), "CONFIRMED_CURRENT");
  await updateDoc(ref(client("admin"), value), {moderationStatus: "rejected", updatedAt: serverTimestamp()});
  assert.equal(await inspect(client("admin"), decision), "CONFIRMED_CHANGED"); assert.equal(submissions, count); assertions += 3;
});
test("7 exact privileged fixture deletion simulates receipt retention/removal without authorizing replay", async () => {
  const value = item("events"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "approved", reviewed(value, before)); await execute(client("admin"), decision);
  assert.equal(await inspect(client("admin"), decision), "CONFIRMED_CURRENT");
  await environment.withSecurityRulesDisabled(async (context) => deleteDoc(ref(context.firestore(), `systemLogs/${decision.id}`)));
  const count = submissions;
  assert.equal(await inspect(client("admin"), decision), "OBSERVED_WITHOUT_RECEIPT");
  assert.equal(await inspect(client("admin"), decision), "OBSERVED_WITHOUT_RECEIPT");
  assert.equal(submissions, count); assert.equal((await fresh(`systemLogs/${decision.id}`)).exists(), false); assertions += 5;
});
test("7 source state with no receipt stays unconfirmed and read-only", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "admin", "rejected", reviewed(value, before)); const count = submissions;
  assert.equal(await inspect(client("admin"), decision), "UNCONFIRMED");
  assert.equal(await inspect(client("admin"), decision), "UNCONFIRMED");
  assert.equal(submissions, count); await assertUnchanged(decision, before); assertions += 3;
});
for (const actor of ["owner", "admin"]) for (const kind of ["news", "events"]) {
  test(`7 ${actor} ${kind}: deleted target is readable as missing while matching receipt remains`, async () => {
    const value = item(kind); await seed(value, fields(value)); const before = await freshData(value);
    const decision = intent(value, actor, "approved", reviewed(value, before));
    await execute(client(actor), decision);
    await environment.withSecurityRulesDisabled(async (context) => deleteDoc(ref(context.firestore(), value)));
    const count = submissions;
    assert.equal((await getDocFromServer(ref(client(actor), value))).exists(), false);
    assert.equal((await lookup(client(actor), decision.id, actor === "owner")).exists(), true);
    assert.equal(await inspect(client(actor), decision), "CONFIRMED_UNAVAILABLE");
    assert.equal(await inspect(client(actor), decision), "CONFIRMED_UNAVAILABLE");
    assert.equal(submissions, count); assertions += 5;
  });
}
test("7 existing conditional Rules MFA permits an unactivated owner; Android must retain its stricter activation gate", async () => {
  const value = item("news"); await seed(value, fields(value)); const before = await freshData(value);
  const decision = intent(value, "unactivatedOwner", "approved", reviewed(value, before));
  await execute(client("unactivatedOwner"), decision);
  assert.equal((await freshData(value)).moderationStatus, "approved"); assertions++;
});
