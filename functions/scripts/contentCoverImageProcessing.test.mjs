import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {existsSync} from "node:fs";
import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {test} from "node:test";
import {promisify} from "node:util";

import {
  CONTENT_COVER_CONTENT_TYPE,
  CONTENT_COVER_EXTENSION,
  CONTENT_COVER_MAXIMUM_OUTPUT_BYTES,
  CONTENT_COVER_MAXIMUM_PIXEL_DIMENSION,
  prepareCanonicalContentCover,
} from "./contentCoverImageProcessing.mjs";

const runFile = promisify(execFile);
const hasSips = existsSync("/usr/bin/sips");

test("canonical content cover converts a 16:9 PNG to bounded JPEG", {skip: !hasSips}, async () => {
  await withTemporaryDirectory(async (directory) => {
    const sourcePath = await createPNG(directory, "source", 2000, 1125);
    const prepared = await prepareCanonicalContentCover(sourcePath);

    assert.equal(prepared.contentType, CONTENT_COVER_CONTENT_TYPE);
    assert.equal(prepared.extension, CONTENT_COVER_EXTENSION);
    assert.equal(prepared.width, CONTENT_COVER_MAXIMUM_PIXEL_DIMENSION);
    assert.equal(prepared.height, 900);
    assert.equal(prepared.quality, 82);
    assert.ok(prepared.bytes.length > 0);
    assert.ok(prepared.bytes.length <= CONTENT_COVER_MAXIMUM_OUTPUT_BYTES);
    assert.deepEqual([...prepared.bytes.subarray(0, 3)], [0xff, 0xd8, 0xff]);
  });
});

test("canonical content cover rejects a non-16:9 source", {skip: !hasSips}, async () => {
  await withTemporaryDirectory(async (directory) => {
    const sourcePath = await createPNG(directory, "square", 100, 100);
    await assert.rejects(
      prepareCanonicalContentCover(sourcePath),
      /must be 16:9/
    );
  });
});

test("canonical content cover rejects an extension with a spoofed signature", async () => {
  await withTemporaryDirectory(async (directory) => {
    const sourcePath = join(directory, "spoofed.png");
    await writeFile(sourcePath, "not an image");
    await assert.rejects(
      prepareCanonicalContentCover(sourcePath),
      /PNG signature is invalid/
    );
  });
});

async function createPNG(directory, name, width, height) {
  const ppmPath = join(directory, `${name}.ppm`);
  const pngPath = join(directory, `${name}.png`);
  const header = Buffer.from(`P6\n${width} ${height}\n255\n`, "ascii");
  const pixels = Buffer.alloc(width * height * 3);
  for (let offset = 0; offset < pixels.length; offset += 3) {
    const pixel = offset / 3;
    pixels[offset] = pixel % 251;
    pixels[offset + 1] = Math.floor(pixel / width) % 241;
    pixels[offset + 2] = 173;
  }
  await writeFile(ppmPath, Buffer.concat([header, pixels]));
  await runFile("/usr/bin/sips", ["-s", "format", "png", ppmPath, "--out", pngPath], {maxBuffer: 1_000_000});
  const bytes = await readFile(pngPath);
  assert.ok(bytes.length > 0);
  return pngPath;
}

async function withTemporaryDirectory(operation) {
  const directory = await mkdtemp(join(tmpdir(), "uac-cover-test-"));
  try {
    await operation(directory);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
}
