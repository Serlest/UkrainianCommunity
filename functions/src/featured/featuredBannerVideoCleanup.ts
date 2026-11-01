import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";
import { adminStorage, db } from "../firebase/admin";
import { bannerVideoAssetCollection, videoAssetID } from "./featuredBannerVideoContract";
import { safeVideoComponent } from "./featuredBannerVideoInspection";
/** Taking the manifest lease and attaching media use the same Firestore transaction boundary.
 * A client cannot reattach an asset after this marks it deleting; generation preconditions
 * prevent an old retry from deleting a later immutable recreation of the same SHA.
 */
export async function reclaimUnreferencedBannerVideo(assetID: string, notNewerThan?: Timestamp): Promise<void> {
    if (!/^[0-9a-f]{64}$/.test(assetID))
        return;
    const ref = db.collection(bannerVideoAssetCollection).doc(assetID);
    const lease = await db.runTransaction(async (tx) => {
        const asset = await tx.get(ref);
        if (!asset.exists || !["ready", "deleting"].includes(asset.get("status")))
            return;
        if (asset.get("status") === "ready" && notNewerThan && asset.get("updatedAt") instanceof Timestamp && asset.get("updatedAt").toMillis() > notNewerThan.toMillis())
            return;
        const id = asset.get("bannerID"), descriptor = asset.get("descriptor"), generation = asset.get("generation");
        if (!safeVideoComponent(id) || !descriptor || !/^[0-9a-f]{64}$/.test(descriptor.sha256) || assetID !== videoAssetID(id, descriptor.sha256)
            || descriptor.assetPath !== `featuredBannerVideos/${id}/${descriptor.sha256}.mp4` || typeof generation !== "string" || !/^\d+$/.test(generation))
            return;
        const presentation = await tx.get(db.collection("featuredBannerPresentations").doc(id));
        if (presentation.get("video.assetID") === assetID)
            return;
        tx.update(ref, { status: "deleting", updatedAt: Timestamp.now() });
        return { path: descriptor.assetPath as string, generation };
    });
    if (!lease)
        return;
    try {
        await adminStorage.bucket().file(lease.path, { generation: lease.generation }).delete({ ignoreNotFound: true });
    }
    catch (error) {
        if ((error as {
            code?: number;
        }).code !== 404)
            throw error;
    }
    await db.runTransaction(async (tx) => { const asset = await tx.get(ref); if (asset.get("status") === "deleting" && asset.get("generation") === lease.generation)
        tx.update(ref, { status: "deleted", updatedAt: Timestamp.now() }); });
}
export const cleanupReplacedFeaturedBannerVideo = onDocumentWritten({ document: "featuredBannerPresentations/{bannerID}", region: "europe-west3", retry: true }, async (event) => {
    const before = event.data?.before.get("video.assetID"), after = event.data?.after.get("video.assetID");
    if (typeof before === "string" && before !== after) {
        const time = Date.parse(event.time);
        if (!Number.isFinite(time))
            throw Error("Missing video event time");
        await reclaimUnreferencedBannerVideo(before, Timestamp.fromMillis(time));
    }
});
/** A bounded daily sweep handles owner cancellation and failed publication. No download of media. */
export const cleanupAbandonedFeaturedBannerVideos = onSchedule({ schedule: "every 24 hours", region: "europe-west3", maxInstances: 1, timeoutSeconds: 120 }, async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 86400000);
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    for (let page = 0; page < 5; page++) {
        let query = db.collection(bannerVideoAssetCollection).where("updatedAt", "<", cutoff).limit(200);
        if (cursor)
            query = query.startAfter(cursor);
        const assets = await query.get();
        for (const asset of assets.docs) {
            if (asset.get("status") === "preparing") {
                const id = asset.get("bannerID"), d = asset.get("descriptor");
                if (!safeVideoComponent(id) || !d || !/^[0-9a-f]{64}$/.test(d.sha256) || asset.id !== videoAssetID(id, d.sha256) || d.assetPath !== `featuredBannerVideos/${id}/${d.sha256}.mp4`)
                    continue;
                let generation: string | undefined;
                try {
                    const [m] = await adminStorage.bucket().file(d.assetPath).getMetadata();
                    generation = m.generation === undefined ? undefined : String(m.generation);
                }
                catch (error) {
                    if ((error as {
                        code?: number;
                    }).code !== 404)
                        throw error;
                }
                await db.runTransaction(async (tx) => { const current = await tx.get(asset.ref); if (current.get("status") === "preparing" && current.get("updatedAt") instanceof Timestamp && current.get("updatedAt").toMillis() < cutoff.toMillis())
                    tx.update(asset.ref, { status: generation ? "deleting" : "deleted", ...(generation ? { generation } : {}), updatedAt: Timestamp.now() }); });
            }
            await reclaimUnreferencedBannerVideo(asset.id, cutoff);
        }
        if (assets.size < 200)
            break;
        cursor = assets.docs.at(-1);
    }
    // Private input files older than the maximum callable lifetime cannot be in flight.
    const bucket = adminStorage.bucket();
    let pageToken: string | undefined;
    for (let page = 0; page < 5; page++) {
        const [files, next] = await bucket.getFiles({ prefix: "featuredBannerVideoUploads/", maxResults: 100, autoPaginate: false, pageToken });
        for (const file of files) {
            const [metadata] = await file.getMetadata();
            if (metadata.generation && Date.parse(metadata.timeCreated ?? "") < cutoff.toMillis())
                await bucket.file(file.name, { generation: metadata.generation }).delete({ ignoreNotFound: true });
        }
        pageToken = next?.pageToken;
        if (!pageToken)
            break;
    }
});
