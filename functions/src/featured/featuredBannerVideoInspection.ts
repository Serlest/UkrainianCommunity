import { createHash } from "node:crypto";
export const bannerVideoLimits = Object.freeze({ bytes: 4 * 1024 * 1024, duration: 15, width: 1280, height: 720, fps: 30 });
export interface BannerVideoDescriptor {
    schemaVersion: 1;
    assetPath: string;
    sha256: string;
    byteCount: number;
    width: number;
    height: number;
    durationSeconds: number;
    framesPerSecond: number;
    codec: "h264";
    hasAudio: boolean;
    audioCodec?: "aac";
}
interface Box {
    type: string;
    start: number;
    end: number;
    data: number;
}
const component = /^[A-Za-z0-9_-]{1,128}$/;
export function safeVideoComponent(value: unknown): value is string { return typeof value === "string" && component.test(value); }
/** Conservative, bounded ISO-BMFF inspection of a prepared nonfragmented MP4.
 * This does not claim bitstream decoding/transcoding. Client metadata is never trusted.
 * Reject anything outside the narrow AVFoundation rendition contract, including external data references.
 */
export function inspectPreparedBannerVideo(bytes: Buffer, bannerID: string): BannerVideoDescriptor {
    if (!safeVideoComponent(bannerID) || !bytes.length || bytes.length > bannerVideoLimits.bytes)
        throw Error("Invalid video size or banner ID");
    let budget = 4096;
    function boxes(start: number, end: number): Box[] {
        const result: Box[] = [];
        for (let p = start; p < end;) {
            if (--budget < 0 || p + 8 > end)
                throw Error("Invalid MP4 atom budget");
            let size = bytes.readUInt32BE(p);
            const type = bytes.toString("ascii", p + 4, p + 8);
            let header = 8;
            // AVAssetWriter uses a 64-bit mdat size even for small outputs.
            if (size === 1) {
                if (p + 16 > end)
                    throw Error("Truncated extended atom");
                size = Number(bytes.readBigUInt64BE(p + 8));
                header = 16;
            }
            if (!Number.isSafeInteger(size) || size < header || p + size > end)
                throw Error("Invalid MP4 atom length");
            result.push({ type, start: p, end: p + size, data: p + header });
            p += size;
        }
        return result;
    }
    function one(list: Box[], type: string): Box { const matches = list.filter(x => x.type === type); if (matches.length !== 1)
        throw Error("Missing or duplicate " + type); return matches[0]; }
    function length(b: Box, n: number) { if (b.end - b.data < n)
        throw Error("Truncated " + b.type); }
    const top = boxes(0, bytes.length), ftyp = one(top, "ftyp"), moov = one(top, "moov"), mdat = one(top, "mdat");
    if (top.some(x => !["ftyp", "moov", "mdat", "free", "skip", "wide"].includes(x.type)) || mdat.end <= mdat.data)
        throw Error("Unsupported MP4 structure");
    length(ftyp, 8);
    if ((ftyp.end - ftyp.data) % 4 !== 0)
        throw Error("Invalid MP4 brands");
    const brands = [];
    for (let p = ftyp.data; p + 4 <= ftyp.end; p += 4)
        if (p !== ftyp.data + 4)
            brands.push(bytes.toString("ascii", p, p + 4));
    if (!brands.some(x => ["isom", "iso2", "avc1", "mp41", "mp42"].includes(x)))
        throw Error("Unsupported MP4 brand");
    const movie = boxes(moov.data, moov.end);
    if (movie.some(x => ["mvex", "cmov"].includes(x.type)))
        throw Error("Fragmented/compressed movie not supported");
    const mvhd = one(movie, "mvhd");
    length(mvhd, 20);
    const movieVersion = bytes[mvhd.data];
    if (movieVersion !== 0 && movieVersion !== 1)
        throw Error("Invalid movie header");
    length(mvhd, movieVersion === 1 ? 32 : 20);
    const movieScale = bytes.readUInt32BE(mvhd.data + (movieVersion === 1 ? 20 : 12));
    if (!movieScale)
        throw Error("Invalid movie timescale");
    const tracks = movie.filter(x => x.type === "trak");
    if (tracks.length < 1 || tracks.length > 2)
        throw Error("Unsupported track count");
    let width = 0, height = 0, duration = 0, fps = 0, videos = 0, audios = 0;
    for (const track of tracks) {
        const trackBoxes = boxes(track.data, track.end), mdia = one(trackBoxes, "mdia"), tkhd = one(trackBoxes, "tkhd"), media = boxes(mdia.data, mdia.end);
        const hdlr = one(media, "hdlr"), mdhd = one(media, "mdhd");
        length(hdlr, 12);
        length(mdhd, 20);
        const kind = bytes.toString("ascii", hdlr.data + 8, hdlr.data + 12);
        if (!["vide", "soun"].includes(kind))
            throw Error("Unsupported media track");
        const v = bytes[mdhd.data];
        if (v !== 0 && v !== 1)
            throw Error("Unsupported media header");
        length(mdhd, v === 1 ? 32 : 20);
        const scale = bytes.readUInt32BE(mdhd.data + (v === 1 ? 20 : 12));
        const ticks = v === 1 ? Number(bytes.readBigUInt64BE(mdhd.data + 24)) : bytes.readUInt32BE(mdhd.data + 16);
        const seconds = ticks / scale;
        if (!scale || !Number.isSafeInteger(ticks) || !Number.isFinite(seconds) || seconds <= 0 || seconds > 15.2)
            throw Error("Invalid media duration");
        const minf = one(media, "minf"), mediaInfo = boxes(minf.data, minf.end), dinf = one(mediaInfo, "dinf"), dref = one(boxes(dinf.data, dinf.end), "dref");
        length(dref, 8);
        const refs = boxes(dref.data + 8, dref.end);
        if (bytes.readUInt32BE(dref.data + 4) !== 1 || refs.length !== 1 || refs[0].type !== "url ")
            throw Error("Unsupported data references");
        length(refs[0], 4);
        if (refs[0].end - refs[0].data !== 4 || bytes.readUInt32BE(refs[0].data) !== 1)
            throw Error("External media is forbidden");
        const stbl = one(mediaInfo, "stbl"), sampleTable = boxes(stbl.data, stbl.end), stsd = one(sampleTable, "stsd"), stts = one(sampleTable, "stts"), stsz = one(sampleTable, "stsz");
        length(stsd, 8);
        const entries = boxes(stsd.data + 8, stsd.end);
        if (bytes.readUInt32BE(stsd.data + 4) !== 1 || entries.length !== 1)
            throw Error("Unsupported sample descriptions");
        const sample = entries[0];
        length(sample, 8);
        if (bytes.readUInt16BE(sample.data + 6) !== 1)
            throw Error("Invalid sample data reference");
        length(stts, 8);
        const timeCount = bytes.readUInt32BE(stts.data + 4);
        if (!timeCount || timeCount > 10000 || stts.end - stts.data !== 8 + 8 * timeCount)
            throw Error("Invalid timing table");
        let samples = 0, time = 0, peakRate = 0;
        for (let p = stts.data + 8; p < stts.end; p += 8) {
            const count = bytes.readUInt32BE(p), delta = bytes.readUInt32BE(p + 4);
            if (!count || !delta)
                throw Error("Invalid sample duration");
            samples += count;
            time += count * delta;
            peakRate = Math.max(peakRate, scale / delta);
        }
        if (!Number.isSafeInteger(time) || !Number.isSafeInteger(samples) || Math.abs(time - ticks) > scale * 0.1)
            throw Error("Inconsistent track timing");
        length(stsz, 12);
        const uniform = bytes.readUInt32BE(stsz.data + 4), count = bytes.readUInt32BE(stsz.data + 8);
        if (count !== samples || count > 100000 || stsz.end - stsz.data !== 12 + (uniform ? 0 : 4 * count))
            throw Error("Invalid sample sizes");
        let total = uniform * count;
        for (let p = stsz.data + 12; !uniform && p < stsz.end; p += 4) {
            const n = bytes.readUInt32BE(p);
            if (!n)
                throw Error("Empty sample");
            total += n;
        }
        if (total <= 0 || total > mdat.end - mdat.data)
            throw Error("Media payload too short");
        const offsets = sampleTable.filter(x => x.type === "stco" || x.type === "co64");
        if (offsets.length !== 1)
            throw Error("Invalid chunk offsets");
        const offset = offsets[0], step = offset.type === "stco" ? 4 : 8;
        length(offset, 8);
        const chunks = bytes.readUInt32BE(offset.data + 4);
        if (!chunks || chunks > 100000 || offset.end - offset.data !== 8 + step * chunks)
            throw Error("Invalid chunk table");
        for (let p = offset.data + 8; p < offset.end; p += step) {
            const n = step === 4 ? bytes.readUInt32BE(p) : Number(bytes.readBigUInt64BE(p));
            if (!Number.isSafeInteger(n) || n < mdat.data || n >= mdat.end)
                throw Error("Media chunk outside payload");
        }
        if (kind === "vide") {
            if (++videos !== 1 || sample.type !== "avc1")
                throw Error("Expected one H.264 track");
            length(sample, 78);
            width = bytes.readUInt16BE(sample.data + 24);
            height = bytes.readUInt16BE(sample.data + 26);
            if (width < 160 || width > 1280 || height < 90 || height > 720 || width % 2 || height % 2 || Math.abs(width / height - 16 / 9) > 0.01)
                throw Error("Invalid video dimensions");
            const avcc = one(boxes(sample.data + 78, sample.end), "avcC");
            length(avcc, 7);
            if (bytes[avcc.data] !== 1)
                throw Error("Invalid AVC configuration");
            // A non-identity display matrix would invalidate the advertised landscape layout.
            length(tkhd, 4);
            const tv = bytes[tkhd.data];
            if (tv !== 0 && tv !== 1)
                throw Error("Invalid track header");
            const matrix = tkhd.data + (tv === 1 ? 52 : 40);
            if (matrix + 44 > tkhd.end)
                throw Error("Truncated track geometry");
            const identity = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824];
            for (let i = 0; i < 9; i++)
                if (bytes.readInt32BE(matrix + 4 * i) !== identity[i])
                    throw Error("Video transform must be normalized");
            if (bytes.readUInt32BE(tkhd.end - 8) !== width * 65536 || bytes.readUInt32BE(tkhd.end - 4) !== height * 65536)
                throw Error("Track dimensions differ");
            const displayTicks = tv === 1 ? Number(bytes.readBigUInt64BE(tkhd.data + 28)) : bytes.readUInt32BE(tkhd.data + 20);
            duration = displayTicks / movieScale;
            fps = peakRate;
            // B-frame/AAC priming can extend mdhd beyond the presented tkhd interval.
            // Bound that slack while using the actual displayed length, not encoder padding.
            if (!Number.isSafeInteger(displayTicks) || !Number.isFinite(duration) || duration < 1 || duration > 15.001 || Math.abs(seconds - duration) > 0.2
                || fps < 1 || fps > 30.01 || samples > 454)
                throw Error("Invalid video presentation duration or frame rate");
        }
        else {
            if (++audios !== 1 || sample.type !== "mp4a")
                throw Error("Expected AAC audio");
            length(sample, 28);
            const channels = bytes.readUInt16BE(sample.data + 16), rate = bytes.readUInt32BE(sample.data + 24) / 65536;
            if (bytes.readUInt16BE(sample.data + 8) !== 0 || channels < 1 || channels > 2 || rate < 8000 || rate > 48000)
                throw Error("Invalid audio parameters");
            const esds = one(boxes(sample.data + 28, sample.end), "esds");
            length(esds, 5);
        }
    }
    if (videos !== 1)
        throw Error("Missing video");
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    return { schemaVersion: 1, assetPath: `featuredBannerVideos/${bannerID}/${sha256}.mp4`, sha256, byteCount: bytes.length, width, height,
        durationSeconds: Math.min(15, duration), framesPerSecond: Math.min(30, fps), codec: "h264", hasAudio: audios === 1, ...(audios ? { audioCodec: "aac" as const } : {}) };
}
