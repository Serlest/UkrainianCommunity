import { createHash, randomUUID } from "node:crypto";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { requireVerifiedActiveUser } from "../auth/context";
import { assertOwner } from "../permissions/userPermissions";
import { adminStorage, db } from "../firebase/admin";
import { bannerVideoLimits, inspectPreparedBannerVideo, safeVideoComponent } from "./featuredBannerVideoInspection";
import { bannerVideoAssetCollection, videoAssetID, readyBannerVideoFromManifest, type BannerVideoPresentation } from "./featuredBannerVideoContract";
async function owner(request: CallableRequest): Promise<string> { const auth = await requireVerifiedActiveUser(request); assertOwner(auth.permissions); return auth.uid; }
export const prepareFeaturedBannerVideo = onCall({ region: "europe-west3", maxInstances: 2, concurrency: 1, memory: "256MiB", timeoutSeconds: 60, enforceAppCheck: false }, async (request): Promise<BannerVideoPresentation> => {
    const uid = await owner(request);
    if (process.env.UAC_BANNER_VIDEO_ENABLED !== "1")
        throw new HttpsError("failed-precondition", "Video banners are not enabled yet.");
    const { bannerID, uploadID } = request.data ?? {};
    if (!safeVideoComponent(bannerID) || !safeVideoComponent(uploadID))
        throw new HttpsError("invalid-argument", "Invalid video upload.");
    const receiptID = createHash("sha256").update(JSON.stringify([uid, bannerID, uploadID])).digest("hex"), receiptRef = db.collection("featuredBannerVideoUploadReceipts").doc(receiptID);
    const previous = await receiptRef.get();
    if (previous.exists) {
        const assetID = previous.get("assetID"), asset = await db.collection(bannerVideoAssetCollection).doc(assetID).get();
        if (asset.get("status") === "ready")
            return readyBannerVideoFromManifest(asset.data(), bannerID, assetID, adminStorage.bucket().name);
        if (asset.get("status") === "deleting")
            throw new HttpsError("aborted", "Video cleanup in progress. Retry later.");
        // Expired unreferenced output can be recreated from the same retained local clip.
        await db.runTransaction(async (tx) => {
            const current = await tx.get(receiptRef), currentAsset = await tx.get(db.collection(bannerVideoAssetCollection).doc(assetID));
            if (current.exists && current.get("assetID") === assetID && (!currentAsset.exists || currentAsset.get("status") === "deleted"))
                tx.delete(receiptRef);
        });
    }
    const bucket = adminStorage.bucket(), source = bucket.file(`featuredBannerVideoUploads/${uid}/${bannerID}/${uploadID}.mp4`);
    const metadata = await source.getMetadata().then(x => x[0]).catch(error => { if ((error as {
        code?: number;
    }).code === 404)
        throw new HttpsError("not-found", "The upload has not completed."); throw error; });
    const size = Number(metadata.size);
    if (!Number.isSafeInteger(size) || size < 1 || size > bannerVideoLimits.bytes || metadata.contentType !== "video/mp4" || !metadata.generation)
        throw new HttpsError("invalid-argument", "Invalid prepared video file.");
    // Pin the generation: a replacement cannot change the bytes after the size check.
    const pinned = bucket.file(source.name, { generation: metadata.generation });
    const [bytes] = await pinned.download();
    if (bytes.length !== size)
        throw new HttpsError("aborted", "Video upload changed.");
    let descriptor;
    try {
        descriptor = inspectPreparedBannerVideo(bytes, bannerID);
    }
    catch {
        throw new HttpsError("invalid-argument", "Use a 1–15 second landscape H.264 MP4, at most 720p, 30fps and 4 MiB.");
    }
    if (await owner(request) !== uid)
        throw new HttpsError("permission-denied", "Session changed.");
    const assetID = videoAssetID(bannerID, descriptor.sha256), reference = db.collection(bannerVideoAssetCollection).doc(assetID), output = bucket.file(descriptor.assetPath);
    // Record the owned output before writing Storage, so a crash cannot leave an untracked public rendition.
    await db.runTransaction(async (tx) => {
        const old = await tx.get(reference);
        if (old.get("status") === "deleting")
            throw new HttpsError("aborted", "Video cleanup in progress. Retry later.");
        if (!old.exists || old.get("status") === "deleted" || old.get("status") === "preparing")
            tx.set(reference, { status: "preparing", bannerID, descriptor, preparedBy: uid, updatedAt: Timestamp.now() });
    });
    const downloadToken = randomUUID();
    try {
        await output.save(bytes, { resumable: false, validation: "crc32c", preconditionOpts: { ifGenerationMatch: 0 }, metadata: { contentType: "video/mp4", cacheControl: "public,max-age=86400,immutable", metadata: { sha256: descriptor.sha256, bannerID, firebaseStorageDownloadTokens: downloadToken } } });
    }
    catch (error) {
        if ((error as {
            code?: number;
        }).code !== 412)
            throw error;
    }
    const [out] = await output.getMetadata();
    if (out.metadata?.sha256 !== descriptor.sha256 || out.metadata?.bannerID !== bannerID || Number(out.size) !== bytes.length || out.contentType !== "video/mp4" || !out.generation)
        throw new HttpsError("failed-precondition", "Video storage verification failed.");
    const token = String(out.metadata?.firebaseStorageDownloadTokens ?? "").split(",")[0];
    if (!token)
        throw new HttpsError("failed-precondition", "Missing video delivery token.");
    const manifest = { status: "ready", bannerID, descriptor, generation: String(out.generation), playbackURL: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(output.name)}?alt=media&token=${encodeURIComponent(token)}`, preparedBy: uid, updatedAt: Timestamp.now() };
    await db.runTransaction(async (transaction) => { const old = await transaction.get(reference); if (old.get("status") === "deleting")
        throw new HttpsError("aborted", "Video cleanup in progress. Retry later."); transaction.set(reference, manifest); transaction.set(receiptRef, { bannerID, assetID, uid, updatedAt: Timestamp.now() }); });
    // The private upload is no longer needed. Failure here must not turn a committed result into a reported failure.
    try {
        await pinned.delete({ ignoreNotFound: true });
    }
    catch { /* Scheduled private-upload cleanup retries abandoned inputs. */ }
    return readyBannerVideoFromManifest(manifest, bannerID, assetID, bucket.name);
});
