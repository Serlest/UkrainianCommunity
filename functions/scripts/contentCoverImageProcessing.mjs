import {execFile} from "node:child_process";
import {mkdtemp, readFile, rm, stat, unlink} from "node:fs/promises";
import {tmpdir} from "node:os";
import {extname, join, resolve} from "node:path";
import {promisify} from "node:util";

const runFile = promisify(execFile);
const supportedExtensions = new Set([".jpg", ".jpeg", ".png", ".webp"]);
const jpegSignature = Buffer.from([0xff, 0xd8, 0xff]);
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export const CONTENT_COVER_CONTENT_TYPE = "image/jpeg";
export const CONTENT_COVER_EXTENSION = ".jpg";
export const CONTENT_COVER_MAXIMUM_INPUT_BYTES = 15_000_000;
export const CONTENT_COVER_MAXIMUM_OUTPUT_BYTES = 1_000_000;
export const CONTENT_COVER_MAXIMUM_PIXEL_DIMENSION = 1600;
export const CONTENT_COVER_MINIMUM_ASPECT_RATIO = 1.65;
export const CONTENT_COVER_MAXIMUM_ASPECT_RATIO = 1.90;

export async function prepareCanonicalContentCover(sourcePath) {
  const absolutePath = resolve(sourcePath);
  const extension = extname(absolutePath).toLowerCase();
  if (!supportedExtensions.has(extension)) {
    throw new Error(`Unsupported content cover extension: ${extension || "(none)"}.`);
  }

  const inputStats = await stat(absolutePath).catch(() => null);
  if (!inputStats?.isFile() || inputStats.size <= 0) {
    throw new Error(`Content cover does not exist or is empty: ${absolutePath}.`);
  }
  if (inputStats.size > CONTENT_COVER_MAXIMUM_INPUT_BYTES) {
    throw new Error(`Content cover exceeds ${CONTENT_COVER_MAXIMUM_INPUT_BYTES} bytes: ${absolutePath}.`);
  }

  const sourceBytes = await readFile(absolutePath);
  verifySourceSignature(sourceBytes, extension, absolutePath);
  const sourceDimensions = await imageDimensions(absolutePath);
  const aspectRatio = sourceDimensions.width / sourceDimensions.height;
  if (aspectRatio < CONTENT_COVER_MINIMUM_ASPECT_RATIO
    || aspectRatio > CONTENT_COVER_MAXIMUM_ASPECT_RATIO) {
    throw new Error(
      `Content cover must be 16:9 (accepted ratio ${CONTENT_COVER_MINIMUM_ASPECT_RATIO}-${CONTENT_COVER_MAXIMUM_ASPECT_RATIO}); `
      + `received ${sourceDimensions.width}x${sourceDimensions.height}.`
    );
  }

  const sourceMaximumDimension = Math.max(sourceDimensions.width, sourceDimensions.height);
  const initialMaximumDimension = Math.min(sourceMaximumDimension, CONTENT_COVER_MAXIMUM_PIXEL_DIMENSION);
  const attempts = uniqueAttempts([
    {maximumDimension: initialMaximumDimension, quality: 82},
    {maximumDimension: initialMaximumDimension, quality: 74},
    {maximumDimension: initialMaximumDimension, quality: 68},
    {maximumDimension: Math.min(initialMaximumDimension, 1400), quality: 72},
    {maximumDimension: Math.min(initialMaximumDimension, 1200), quality: 68},
    {maximumDimension: Math.min(initialMaximumDimension, 1000), quality: 62},
  ]);

  const temporaryDirectory = await mkdtemp(join(tmpdir(), "uac-content-cover-"));
  const outputPath = join(temporaryDirectory, "cover.jpg");
  try {
    for (const attempt of attempts) {
      await unlink(outputPath).catch(() => undefined);
      const argumentsList = [
        "-s", "format", "jpeg",
        "-s", "formatOptions", String(attempt.quality),
      ];
      if (sourceMaximumDimension > attempt.maximumDimension) {
        argumentsList.push("-Z", String(attempt.maximumDimension));
      }
      argumentsList.push(absolutePath, "--out", outputPath);

      try {
        await runFile("/usr/bin/sips", argumentsList, {maxBuffer: 1_000_000});
      } catch {
        throw new Error(`Content cover conversion failed: ${absolutePath}.`);
      }

      const bytes = await readFile(outputPath);
      verifyJPEGSignature(bytes, outputPath);
      if (bytes.length > 0 && bytes.length <= CONTENT_COVER_MAXIMUM_OUTPUT_BYTES) {
        const dimensions = await imageDimensions(outputPath);
        return {
          bytes,
          contentType: CONTENT_COVER_CONTENT_TYPE,
          extension: CONTENT_COVER_EXTENSION,
          width: dimensions.width,
          height: dimensions.height,
          quality: attempt.quality,
        };
      }
    }
  } finally {
    await rm(temporaryDirectory, {recursive: true, force: true});
  }

  throw new Error(`Content cover cannot be reduced below ${CONTENT_COVER_MAXIMUM_OUTPUT_BYTES} bytes.`);
}

async function imageDimensions(absolutePath) {
  let stdout;
  try {
    ({stdout} = await runFile(
      "/usr/bin/sips",
      ["-g", "pixelWidth", "-g", "pixelHeight", absolutePath],
      {encoding: "utf8", maxBuffer: 1_000_000}
    ));
  } catch {
    throw new Error(`Content cover dimensions cannot be read: ${absolutePath}.`);
  }

  const width = Number(/pixelWidth:\s*(\d+)/.exec(stdout)?.[1]);
  const height = Number(/pixelHeight:\s*(\d+)/.exec(stdout)?.[1]);
  if (!Number.isInteger(width) || width <= 0 || !Number.isInteger(height) || height <= 0) {
    throw new Error(`Content cover dimensions are invalid: ${absolutePath}.`);
  }
  return {width, height};
}

function verifySourceSignature(bytes, extension, label) {
  if ([".jpg", ".jpeg"].includes(extension)) {
    verifyJPEGSignature(bytes, label);
    return;
  }
  if (extension === ".png") {
    if (!startsWith(bytes, pngSignature)) throw new Error(`Content cover PNG signature is invalid: ${label}.`);
    return;
  }
  const isWebP = bytes.length >= 12
    && bytes.subarray(0, 4).toString("ascii") === "RIFF"
    && bytes.subarray(8, 12).toString("ascii") === "WEBP";
  if (!isWebP) throw new Error(`Content cover WebP signature is invalid: ${label}.`);
}

function verifyJPEGSignature(bytes, label) {
  if (!startsWith(bytes, jpegSignature)) throw new Error(`Content cover JPEG signature is invalid: ${label}.`);
}

function startsWith(bytes, signature) {
  return bytes.length >= signature.length && bytes.subarray(0, signature.length).equals(signature);
}

function uniqueAttempts(attempts) {
  const seen = new Set();
  return attempts.filter((attempt) => {
    const key = `${attempt.maximumDimension}:${attempt.quality}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
