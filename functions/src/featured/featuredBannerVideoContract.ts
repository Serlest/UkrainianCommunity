import { createHash } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { type BannerVideoDescriptor, safeVideoComponent } from "./featuredBannerVideoInspection";
export const bannerVideoAssetCollection = "featuredBannerVideoAssets";
export interface BannerVideoPresentation {
    assetID: string;
    descriptor: BannerVideoDescriptor;
    playbackURL: string;
}
function record(x: unknown): x is Record<string, unknown> { return !!x && typeof x === "object" && !Array.isArray(x); }
export function parseVideoAssetID(x: unknown): string | undefined {
    if (x === undefined || x === null)
        return undefined;
    if (!safeVideoComponent(x))
        throw new HttpsError("invalid-argument", "Invalid prepared video reference.");
    return x;
}
export function videoAssetID(bannerID: string, sha256: string): string {
    // SHA is already validated by the inspector. Hash of this pair keeps IDs bounded.
    if (!safeVideoComponent(bannerID) || !/^[0-9a-f]{64}$/.test(sha256))
        throw Error("Invalid video identity");
    return createHash("sha256").update(bannerID + ":" + sha256).digest("hex");
}
export function readyBannerVideoFromManifest(value: unknown, bannerID: string, assetID: string, bucket: string): BannerVideoPresentation {
    const fail = () => new HttpsError("failed-precondition", "The video is unavailable or has not passed verification.");
    if (!record(value) || value.status !== "ready" || value.bannerID !== bannerID || !record(value.descriptor) || typeof value.playbackURL !== "string" || typeof value.generation !== "string" || !/^\d+$/.test(value.generation))
        throw fail();
    const d = value.descriptor;
    if (d.schemaVersion !== 1 || typeof d.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(d.sha256) || assetID !== videoAssetID(bannerID, d.sha256)
        || d.assetPath !== `featuredBannerVideos/${bannerID}/${d.sha256}.mp4` || !Number.isInteger(d.byteCount) || Number(d.byteCount) < 1 || Number(d.byteCount) > 4 * 1024 * 1024
        || !Number.isInteger(d.width) || !Number.isInteger(d.height) || Number(d.width) < 160 || Number(d.width) > 1280 || Number(d.height) < 90 || Number(d.height) > 720
        || Number(d.width) % 2 || Number(d.height) % 2 || Math.abs(Number(d.width) / Number(d.height) - 16 / 9) > 0.01
        || typeof d.durationSeconds !== "number" || !Number.isFinite(d.durationSeconds) || d.durationSeconds < 1 || d.durationSeconds > 15
        || typeof d.framesPerSecond !== "number" || !Number.isFinite(d.framesPerSecond) || d.framesPerSecond < 1 || d.framesPerSecond > 30
        || d.codec !== "h264" || typeof d.hasAudio !== "boolean" || (d.hasAudio ? d.audioCodec !== "aac" : d.audioCodec !== undefined))
        throw fail();
    let url: URL;
    try {
        url = new URL(value.playbackURL);
    }
    catch {
        throw fail();
    }
    if (url.protocol !== "https:" || url.hostname !== "firebasestorage.googleapis.com" || url.username || url.password || url.port || url.hash
        || url.pathname !== `/v0/b/${bucket}/o/${encodeURIComponent(String(d.assetPath))}` || url.searchParams.get("alt") !== "media" || !url.searchParams.get("token"))
        throw fail();
    const descriptor: BannerVideoDescriptor = { schemaVersion: 1, assetPath: String(d.assetPath), sha256: d.sha256, byteCount: Number(d.byteCount), width: Number(d.width), height: Number(d.height), durationSeconds: d.durationSeconds, framesPerSecond: d.framesPerSecond, codec: "h264", hasAudio: d.hasAudio, ...(d.hasAudio ? { audioCodec: "aac" } : {}) };
    return { assetID, descriptor, playbackURL: url.toString() };
}
/** Never let a pre-video editor silently erase or retain a hidden video on a changed poster. */
export function assertVideoEditorVersion(version: number | undefined, existingVideo: unknown): void {
    if (existingVideo != null && version !== 3)
        throw new HttpsError("failed-precondition", "Update UAC to edit this video banner.");
}
