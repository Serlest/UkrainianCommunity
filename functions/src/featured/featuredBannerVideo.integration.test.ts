import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { ref, uploadBytes, getMetadata, deleteObject } from "firebase/storage";
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Timestamp } from "firebase-admin/firestore";
import { adminStorage, db } from "../firebase/admin";
import { seedCurrentLegalForIntegration } from "../auth/legalIntegrationFixture";
import { prepareFeaturedBannerVideo } from "./featuredBannerVideoPreparation";
import { saveFeaturedBanner, getFeaturedBannerPresentations, deleteFeaturedBanner } from "./featuredBannerMutations";
import { bannerVideoAssetCollection } from "./featuredBannerVideoContract";
import { reclaimUnreferencedBannerVideo } from "./featuredBannerVideoCleanup";
const req = (uid: string | undefined, data: unknown, totp = true) => ({ data, auth: uid ? { uid, token: { email_verified: true, firebase: { sign_in_second_factor: totp ? "totp" : undefined } } } : undefined }) as never;
test("video preparation and publication enforce roles, readback, replay, legacy isolation and safe reclaim", { skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST }, async () => {
    assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
    const id = "video-" + randomUUID(), uid = "video-owner", member = "video-member", admin = "video-admin", uploadID = randomUUID(), bucket = adminStorage.bucket();
    for (const [user, role] of [[uid, "owner"], [member, "user"], [admin, "admin"]])
        await db.doc(`users/${user}`).set({ globalRole: role, accountStatus: "active", createdAt: Timestamp.now(), requiresMultiFactorAuth: role === "owner" });
    await seedCurrentLegalForIntegration(uid, member, admin);
    const oldFlag = process.env.UAC_BANNER_VIDEO_ENABLED;
    process.env.UAC_BANNER_VIDEO_ENABLED = "1";
    let assetID: string | undefined;
    try {
        const [fireHost, firePort] = process.env.FIRESTORE_EMULATOR_HOST!.split(":"), [storageHost, storagePort] = process.env.FIREBASE_STORAGE_EMULATOR_HOST!.replace(/^https?:\/\//, "").split(":");
        const rules = await initializeTestEnvironment({ projectId: process.env.GCLOUD_PROJECT!, firestore: { host: fireHost, port: Number(firePort) }, storage: { host: storageHost, port: Number(storagePort) } });
        try {
            const ownerClaims = { email_verified: true, firebase: { sign_in_provider: "password" as const, sign_in_second_factor: "totp" } };
            const ownerStore = rules.authenticatedContext(uid, ownerClaims).storage(`gs://${bucket.name}`);
            const memberStore = rules.authenticatedContext(member, { email_verified: true }).storage(`gs://${bucket.name}`);
            const privatePath = `featuredBannerVideoUploads/${uid}/${id}/rules-${uploadID}.mp4`, bytes = readFileSync(join(__dirname, "../../src/featured/fixtures/banner-video-640x360.mp4"));
            await assertSucceeds(uploadBytes(ref(ownerStore, privatePath), bytes, { contentType: "video/mp4" }));
            await assertFails(getMetadata(ref(ownerStore, privatePath)));
            await assertFails(getMetadata(ref(rules.unauthenticatedContext().storage(`gs://${bucket.name}`), privatePath)));
            await assertFails(uploadBytes(ref(memberStore, `featuredBannerVideoUploads/${member}/${id}/${uploadID}.mp4`), bytes, { contentType: "video/mp4" }));
            await assertFails(uploadBytes(ref(ownerStore, `featuredBannerVideoUploads/${member}/${id}/${uploadID}.mp4`), bytes, { contentType: "video/mp4" }));
            await assertFails(uploadBytes(ref(ownerStore, `featuredBannerVideos/${id}/forged.mp4`), bytes, { contentType: "video/mp4" }));
            await assertSucceeds(deleteObject(ref(ownerStore, privatePath)));
        }
        finally {
            await rules.cleanup();
        }
        const source = bucket.file(`featuredBannerVideoUploads/${uid}/${id}/${uploadID}.mp4`);
        await source.save(readFileSync(join(__dirname, "../../src/featured/fixtures/banner-video-640x360.mp4")), { metadata: { contentType: "video/mp4" } });
        for (const user of [undefined, member, admin])
            await assert.rejects(prepareFeaturedBannerVideo.run(req(user, { bannerID: id, uploadID })));
        await assert.rejects(prepareFeaturedBannerVideo.run(req(uid, { bannerID: id, uploadID }, false)));
        await assert.rejects(prepareFeaturedBannerVideo.run(req(uid, { bannerID: "../foreign", uploadID })));
        const media = await prepareFeaturedBannerVideo.run(req(uid, { bannerID: id, uploadID }));
        assetID = media.assetID;
        assert.equal(media.descriptor.width, 640);
        assert.equal((await source.exists())[0], false);
        assert.deepEqual(await prepareFeaturedBannerVideo.run(req(uid, { bannerID: id, uploadID })), media, "Lost reply must not require a deleted input upload");
        const draft = { id, imageURL: "https://example.com/poster.jpg", title: "Video", actionType: "none", regionScope: "allAustria", visibleSections: ["home"], displayDurationSeconds: 8, priority: 0, isActive: true, presentationVersion: 3, videoAssetID: assetID, textAppearance: { titleColorHex: "#FFFFFF" } };
        await assert.rejects(saveFeaturedBanner.run(req(uid, { mode: "create", banner: { ...draft, videoAssetID: randomUUID() }, operationID: randomUUID() })));
        const command = { mode: "create", banner: draft, operationID: randomUUID(), principalID: uid };
        await saveFeaturedBanner.run(req(uid, command));
        await saveFeaturedBanner.run(req(uid, command));
        const banner = await db.doc(`featuredBanners/${id}`).get();
        for (const key of ["video", "videoAssetID", "presentationVersion"])
            assert.equal(banner.get(key), undefined);
        const visible = await getFeaturedBannerPresentations.run(req(undefined, { ids: [id] }));
        assert.deepEqual((visible.presentations[0] as Record<string, unknown>).video, media);
        assert.equal(JSON.stringify(visible).includes(uid), false);
        await assert.rejects(saveFeaturedBanner.run(req(uid, { mode: "update", banner: { ...draft, presentationVersion: 2 } })), { code: "failed-precondition" });
        process.env.UAC_BANNER_VIDEO_ENABLED = "0";
        const rolledBack = await getFeaturedBannerPresentations.run(req(undefined, { ids: [id] }));
        assert.equal((rolledBack.presentations[0] as Record<string, unknown>).video, undefined);
        const ownerView = await getFeaturedBannerPresentations.run(req(uid, { ids: [id], includeInactive: true }));
        assert.deepEqual((ownerView.presentations[0] as Record<string, unknown>).video, media);
        await saveFeaturedBanner.run(req(uid, { mode: "update", banner: { ...draft, title: "Retained during rollback" }, operationID: randomUUID() }));
        assert.equal((await db.doc(`featuredBannerPresentations/${id}`).get()).get("video.assetID"), assetID);
        process.env.UAC_BANNER_VIDEO_ENABLED = "1";
        await reclaimUnreferencedBannerVideo(assetID);
        assert.equal((await bucket.file(media.descriptor.assetPath).exists())[0], true, "Referenced asset retained");
        await saveFeaturedBanner.run(req(uid, { mode: "update", banner: { ...draft, videoAssetID: null }, operationID: randomUUID() }));
        await reclaimUnreferencedBannerVideo(assetID);
        assert.equal((await bucket.file(media.descriptor.assetPath).exists())[0], false);
        await assert.rejects(saveFeaturedBanner.run(req(uid, { mode: "update", banner: draft, operationID: randomUUID() })), { code: "failed-precondition" });
        await source.save(readFileSync(join(__dirname, "../../src/featured/fixtures/banner-video-640x360.mp4")), { metadata: { contentType: "video/mp4" } });
        const recreated = await prepareFeaturedBannerVideo.run(req(uid, { bannerID: id, uploadID }));
        assert.equal(recreated.assetID, assetID);
        await reclaimUnreferencedBannerVideo(assetID, Timestamp.fromMillis(0));
        assert.equal((await bucket.file(recreated.descriptor.assetPath).exists())[0], true, "Old cleanup events must not consume a fresh upload");
        await reclaimUnreferencedBannerVideo(assetID);
        await deleteFeaturedBanner.run(req(uid, { id }));
    }
    finally {
        if (oldFlag === undefined)
            delete process.env.UAC_BANNER_VIDEO_ENABLED;
        else
            process.env.UAC_BANNER_VIDEO_ENABLED = oldFlag;
        for (const path of [`featuredBanners/${id}`, `featuredBannerPresentations/${id}`, `bannerMeasurementHistory/${id}`, ...[uid, member, admin].map(x => `users/${x}`), ...(assetID ? [`${bannerVideoAssetCollection}/${assetID}`] : [])])
            await db.doc(path).delete();
    }
});
