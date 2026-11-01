import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import inspection from '../lib/featured/featuredBannerVideoInspection.js';

// Run the iOS FeaturedBannerVideoPreparationTests first. These are actual native
// encodes, not client metadata or hand-written MP4 headers.
const directory = process.argv[2];
assert.ok(directory, 'Provide the directory containing the native test renditions.');
for (const [file, seconds, audio] of [
  ['video-15s.mp4', 15, true],
  ['video-1s.mp4', 1, true],
  ['gif-0.4.mp4', 1.2, false],
  ['gif-0.05.mp4', 1, false],
]) {
  const descriptor = inspection.inspectPreparedBannerVideo(readFileSync(resolve(directory, file)), 'native-contract');
  assert.ok(Math.abs(descriptor.durationSeconds - seconds) < 0.05, `${file}: unexpected presentation duration`);
  assert.equal(descriptor.hasAudio, audio, `${file}: unexpected audio`);
  console.log(JSON.stringify({file, ...descriptor}));
}
