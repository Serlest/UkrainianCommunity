import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { inspectPreparedBannerVideo } from "./featuredBannerVideoInspection";
import { assertVideoEditorVersion, readyBannerVideoFromManifest, videoAssetID, parseVideoAssetID } from "./featuredBannerVideoContract";
import { parseFeaturedBannerDraft, canonicalFeaturedBannerData } from "./featuredBannerMutations";
import { Timestamp } from "firebase-admin/firestore";
const fixture = () => readFileSync(join(__dirname, "../../src/featured/fixtures/banner-video-640x360.mp4"));
const bucket = "test.firebasestorage.app";
function manifest() { const descriptor = inspectPreparedBannerVideo(fixture(), "banner-1"); return { status: "ready", bannerID: "banner-1", generation: "123", descriptor, playbackURL: `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(descriptor.assetPath)}?alt=media&token=test` }; }
test("inspects actual AVAssetWriter MP4 including extended mdat", () => { const d = inspectPreparedBannerVideo(fixture(), "banner-1"); assert.equal(d.width, 640); assert.equal(d.height, 360); assert.equal(d.durationSeconds, 2); assert.equal(d.framesPerSecond, 30); assert.equal(d.hasAudio, false); assert.match(d.sha256, /^[a-f0-9]{64}$/); });
test("rejects corrupted/truncated/oversized/non-MP4 bytes and foreign ID", () => {
    for (const b of [Buffer.from("not a video"), fixture().subarray(0, 100), Buffer.alloc(4 * 1024 * 1024 + 1)])
        assert.throws(() => inspectPreparedBannerVideo(b, "banner-1"));
    assert.throws(() => inspectPreparedBannerVideo(fixture(), "../foreign"));
    const broken = fixture();
    broken.writeUInt32BE(0, 0);
    assert.throws(() => inspectPreparedBannerVideo(broken, "banner-1"));
    const extended = fixture();
    extended.writeBigUInt64BE(2n ** 63n, 36);
    assert.throws(() => inspectPreparedBannerVideo(extended, "banner-1"));
});
test("rejects external references, unsupported codec and transforms", () => {
    for (const [name, offset, value] of [["url ", 4, 0], ["avc1", 0, "encv"], ["hdlr", 12, "hint"]] as const) {
        const b = fixture(), p = b.indexOf(name);
        assert.ok(p >= 0);
        if (typeof value === "number")
            b.writeUInt32BE(value, p + offset);
        else
            b.write(value, p + offset, "ascii");
        assert.throws(() => inspectPreparedBannerVideo(b, "banner-1"));
    }
    const rotated = fixture(), p = rotated.indexOf("tkhd");
    assert.ok(p >= 0);
    rotated.writeInt32BE(0, p + 44);
    assert.throws(() => inspectPreparedBannerVideo(rotated, "banner-1"));
});
test("ready manifests are bound to their banner, digest, delivery host and generation", () => {
    const m = manifest(), id = videoAssetID(m.bannerID, m.descriptor.sha256);
    assert.equal(readyBannerVideoFromManifest(m, "banner-1", id, bucket).assetID, id);
    for (const patch of [{ status: "processing" }, { status: "deleting" }, { bannerID: "foreign" }, { generation: "bad" }, { playbackURL: "https://evil.test/video.mp4" }, { playbackURL: m.playbackURL.replace(bucket, "foreign-bucket") }, { descriptor: { ...m.descriptor, width: 1920 } }, { descriptor: { ...m.descriptor, durationSeconds: NaN } }, { descriptor: { ...m.descriptor, framesPerSecond: 31 } }])
        assert.throws(() => readyBannerVideoFromManifest({ ...m, ...patch }, "banner-1", id, bucket));
    assert.throws(() => readyBannerVideoFromManifest(m, "banner-2", id, bucket));
});
test("old editors cannot overwrite video; removal requires version3", () => { for (const version of [undefined, 1, 2])
    assert.throws(() => assertVideoEditorVersion(version, { assetID: "x" })); assert.doesNotThrow(() => assertVideoEditorVersion(3, { assetID: "x" })); assert.doesNotThrow(() => assertVideoEditorVersion(2, null)); assert.equal(parseVideoAssetID(null), undefined); assert.throws(() => parseVideoAssetID("https://arbitrary.test/file")); });
test("video version3 still preserves exact legacy banner shape and text/countdown", () => {
    const id = videoAssetID("banner-1", manifest().descriptor.sha256), p = parseFeaturedBannerDraft({ id: "banner-1", imageURL: "https://example.com/poster.jpg", actionType: "none", regionScope: "allAustria", visibleSections: ["home"], displayDurationSeconds: 8, priority: 0, isActive: true, presentationVersion: 3, videoAssetID: id, textAppearance: { titleColorHex: "#abcdef" } });
    assert.equal(p.videoAssetID, id);
    assert.equal(p.textAppearance?.titleColorHex, "#ABCDEF");
    const data = canonicalFeaturedBannerData(p, "owner", Timestamp.now());
    for (const key of ["video", "videoAssetID", "presentationVersion"])
        assert.equal(key in data, false);
});
test("real AVAssetExportSession AAC/H264 output uses presented duration instead of B-frame padding", () => {
    const bytes = readFileSync(join(__dirname, "../../src/featured/fixtures/banner-video-audio.mp4"));
    const d = inspectPreparedBannerVideo(bytes, "audio-banner");
    assert.equal(d.hasAudio, true);
    assert.equal(d.audioCodec, "aac");
    assert.equal(d.durationSeconds, 2);
    assert.equal(d.framesPerSecond, 30);
});
