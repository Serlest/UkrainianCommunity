import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {test} from "node:test";

import {initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore, Timestamp} from "firebase-admin/firestore";
import {initializeApp as initializeClientApp, deleteApp} from "firebase/app";
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword, signOut} from "firebase/auth";
import {getFirestore, connectFirestoreEmulator, collection, getDocs, orderBy, query,
  where} from "firebase/firestore";
import {getFunctions, connectFunctionsEmulator, httpsCallable} from "firebase/functions";

const projectID = "demo-uac-banner-journey";
const enabled = process.env.UAC_BANNER_JOURNEY === "1";

test("verified choice, banner events and owner report use real SDK and callable boundaries", {
  skip: !enabled,
}, async () => {
  assert.equal(process.env.GCLOUD_PROJECT, projectID);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:28080");
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, "127.0.0.1:19099");

  const suffix = randomUUID();
  const userID = `banner-user-${suffix}`;
  const ownerID = `banner-owner-${suffix}`;
  const bannerID = `banner-${suffix}`;
  const password = `Emulator-${suffix}!`;
  const admin = initializeAdminApp({projectId: projectID}, `admin-${suffix}`);
  const adminAuth = getAdminAuth(admin);
  const database = getAdminFirestore(admin);
  const client = initializeClientApp({projectId: projectID, apiKey: "fake-api-key",
    appId: "1:123456789:ios:0123456789abcdef"}, `client-${suffix}`);
  const auth = getAuth(client);
  connectAuthEmulator(auth, "http://127.0.0.1:19099", {disableWarnings: true});
  const firestore = getFirestore(client);
  connectFirestoreEmulator(firestore, "127.0.0.1", 28080);
  const functions = getFunctions(client, "europe-west3");
  connectFunctionsEmulator(functions, "127.0.0.1", 15001);

  try {
    await Promise.all([
      adminAuth.createUser({uid: userID, email: `${userID}@uac.test`, password, emailVerified: true}),
      adminAuth.createUser({uid: ownerID, email: `${ownerID}@uac.test`, password, emailVerified: true}),
    ]);
    await Promise.all([
      database.doc("legalDocuments/terms").set({activeVersion: "2026.14"}),
      database.doc("legalDocuments/privacy").set({activeVersion: "2026.21"}),
      database.doc(`users/${userID}`).set({id: userID, createdAt: Timestamp.now(),
        accountStatus: "active", blockState: "active",
        globalRole: "user", acceptedTermsVersion: "2026.14", acceptedPrivacyVersion: "2026.21"}),
      database.doc(`users/${ownerID}`).set({id: ownerID, createdAt: Timestamp.now(),
        accountStatus: "active", blockState: "active",
        globalRole: "owner", requiresMultiFactorAuth: false,
        acceptedTermsVersion: "2026.14", acceptedPrivacyVersion: "2026.21"}),
      database.doc(`featuredBanners/${bannerID}`).set({id: bannerID, isActive: true,
        visibleSections: ["home"], actionType: "externalURL",
        startsAt: Timestamp.fromMillis(Date.now() - 60_000)}),
    ]);

    await signInWithEmailAndPassword(auth, `${userID}@uac.test`, password);
    const getConsent = httpsCallable(functions, "getBannerMeasurementConsent");
    const choose = httpsCallable(functions, "updateBannerMeasurementConsent");
    const record = httpsCallable(functions, "recordBannerMeasurement");
    assert.deepEqual((await getConsent()).data, {available: true, enabled: false, consentID: null, allowsRegion: false});

    const consentID = randomUUID();
    const event = kind => ({id: randomUUID(), consentID, bannerID, section: "home", kind,
      occurredAtMilliseconds: Date.now()});
    await assert.rejects(record(event("impression")), {code: "functions/failed-precondition"});
    assert.deepEqual((await choose({enabled: true, consentID, locale: "uk",
      privacyVersion: "2026.21", disclosureVersion: "2026-10-12.1"})).data,
    {enabled: true, consentID});
    assert.deepEqual((await getConsent()).data, {available: true, enabled: true, consentID, allowsRegion: false});

    const impression = event("impression");
    const click = event("click");
    assert.deepEqual((await record(impression)).data, {counted: true, duplicate: false});
    assert.deepEqual((await record(impression)).data, {counted: true, duplicate: true});
    assert.deepEqual((await record(click)).data, {counted: true, duplicate: false});

    const day = new Date().toISOString().slice(0, 10);
    const reportQuery = query(collection(firestore, "bannerMeasurementDailyShards"),
      where("day", ">=", day), where("day", "<=", day), orderBy("day"));
    await assert.rejects(getDocs(reportQuery), {code: "permission-denied"});
    await signOut(auth);
    await signInWithEmailAndPassword(auth, `${ownerID}@uac.test`, password);
    const report = await getDocs(reportQuery);
    const rows = report.docs.filter(doc => doc.data().bannerID === bannerID);
    assert.equal(rows.reduce((sum, doc) => sum + doc.data().impressions, 0), 1);
    assert.equal(rows.reduce((sum, doc) => sum + doc.data().clicks, 0), 1);

    await signOut(auth);
    await signInWithEmailAndPassword(auth, `${userID}@uac.test`, password);
    assert.deepEqual((await choose({enabled: false, consentID, locale: "uk",
      privacyVersion: "2026.21", disclosureVersion: "2026-10-12.1"})).data,
    {enabled: false, consentID});
    await assert.rejects(record(event("click")), {code: "functions/failed-precondition"});
  } finally {
    await deleteApp(client);
  }
});
