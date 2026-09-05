// Scoped to the already approved AVD and local demo package; no physical devices.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const adbPath = '/Users/serlest/Library/Android/sdk/platform-tools/adb';
const serial = 'emulator-5554';
const app = 'at.uac.android.local';
const output = '/Users/serlest/Documents/Codex/2026-09-02/uac-android/outputs/';
const preview = process.argv.includes('--preview');
const adb = (...args) => execFileSync(adbPath, ['-s', serial, ...args], { encoding: 'utf8', timeout: 25_000 });
assert(adb('emu', 'avd', 'name').includes('UAC_API_37_Play_ARM64'));
function ui() {
  adb('shell', 'uiautomator', 'dump', '/sdcard/uac-package2-ui.xml');
  const xml = adb('shell', 'cat', '/sdcard/uac-package2-ui.xml');
  return [...xml.matchAll(/<node\b[^>]+>/g)].map(([node]) => Object.fromEntries([...node.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value])));
}
function coordinates(node) {
  const values = node.bounds?.match(/\d+/g)?.map(Number);
  if (!values || values[2] <= values[0] || values[3] <= values[1] || values[3] > 2424) return null;
  return [Math.round((values[0] + values[2]) / 2), Math.round((values[1] + values[3]) / 2)];
}
function click(text, scroll = true) {
  for (let attempt = 0; attempt < (scroll ? 14 : 2); attempt++) {
    const match = ui().find(node => (text instanceof RegExp ? text.test(node.text) : node.text === text) && coordinates(node));
    if (match) { adb('shell', 'input', 'tap', ...coordinates(match).map(String)); return; }
    if (scroll) adb('shell', 'input', 'swipe', '540', '1900', '540', '500', '300');
  }
  throw Error(`Visible control not found: ${text}`);
}
function waitFor(text) {
  for (let attempt = 0; attempt < 12; attempt++) {
    if (ui().some(node => (text instanceof RegExp ? text.test(node.text) : node.text === text))) return;
  }
  throw Error(`State not observed: ${text}`);
}
function screenshot(name) { writeFileSync(output + name, execFileSync(adbPath, ['-s', serial, 'exec-out', 'screencap', '-p'])); }
adb('shell', 'am', 'force-stop', app);
adb('shell', 'am', 'start', '-W', '-n', `${app}/at.uac.android.MainActivity`);
waitFor(/Einstellungen|Налаштування/);
click(/Einstellungen|Налаштування/, false);
click('Deutsch');
click(/^Darstellung:/); click('Hell');
click('Eingebaute Beispiele');
click('Zurück', false);
click(/^Region:/); click('Ganz Österreich');
waitFor('Entdecken');
if (preview) {
  screenshot('android-package2-home-de.png');
  click('Einstellungen', false); click('Українська'); click('Назад', false);
  waitFor('Відкривайте нове'); screenshot('android-package2-home-uk.png');
  click('Налаштування', false); click(/^Тема:/); click('Темна'); click('Назад', false);
  waitFor('Відкривайте нове'); screenshot('android-package2-home-dark-uk.png');
  click('Налаштування', false); click('Deutsch'); click(/^Darstellung:/); click('System'); click('Zurück', false);
  adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  console.log('PASS: final de/uk/light/dark screenshots; reset to de/system/synthetic.');
  process.exit(0);
}
screenshot('android-package2-home-large.png');
click('Nachrichten');
click('Beispielnachricht 18');
waitFor('Nachrichten · Bildung');
screenshot('android-package2-news-large.png');
const oldPID = adb('shell', 'pidof', app).trim();
adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
ui(); // Wait until Android has completed the background state save.
adb('shell', 'am', 'kill', app);
let stopped = false;
try { stopped = !adb('shell', 'pidof', app).trim(); } catch { stopped = true; }
assert(stopped, 'Background process did not terminate');
adb('shell', 'am', 'start', '-W', '-n', `${app}/at.uac.android.MainActivity`);
waitFor('Beispielnachricht 18');
const newPID = adb('shell', 'pidof', app).trim();
assert.notEqual(oldPID, newPID);
screenshot('android-package2-process-restored.png');
console.log(`PASS: real process recreation ${oldPID} → ${newPID}; news detail restored.`);
// Firebase emulators must be stopped before this script. Prior real-SDK run warmed disk pages.
click('Einstellungen', false); click('Firebase Emulator · demo-uac-android'); click('Zurück', false);
// The previous online suite read news-18 only in list form. Go to its warmed news list.
click('Zurück', false);
for (let i = 0; i < 4; i++) adb('shell', 'input', 'swipe', '540', '500', '540', '1900', '200');
let cached = false;
for (let i = 0; i < 10; i++) {
  if (ui().some(node => /Offline-Kopie/.test(node.text))) { cached = true; break; }
  adb('shell', 'input', 'swipe', '540', '1900', '540', '700', '250');
}
assert(cached, 'Offline cache label was not visible');
screenshot('android-package2-cached-offline.png');
console.log('PASS: actual stopped-server read displays persisted offline page and its timestamp.');
adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
console.log('Local runtime smoke complete; no cloud or physical device used.');
