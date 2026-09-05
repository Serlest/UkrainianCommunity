import {readFileSync, writeFileSync, mkdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {resolve} from "node:path";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const {androidPushResourceKey} = require("../lib/notifications/androidPush.js");
const repository = fileURLToPath(new URL("../../", import.meta.url));
const outputDirectory = process.argv[2];
if (!outputDirectory || !outputDirectory.startsWith("/") || process.argv.length !== 3) {
  throw new Error("Provide one absolute output directory for generated resource review files.");
}
const inputs = ["functions/src/index.ts", "functions/src/notifications/inboxPushDelivery.ts",
  "functions/src/notifications/workflowNotifications.ts", "functions/src/organizations/organizationRequestRetention.ts"];
const keys = new Set();
const pattern = /["']((?:notifications\.(?:push|inbox)|account_status_alert)\.[a-z_.]+|content_planning\.title)["']/g;
for (const input of inputs) {
  for (const match of readFileSync(resolve(repository, input), "utf8").matchAll(pattern)) keys.add(match[1]);
}
const strings = JSON.parse(readFileSync(resolve(repository,
  "UkrainianCommunity/Localization/Localizable.xcstrings"), "utf8")).strings;
const names = [...keys].map(androidPushResourceKey);
if (names.some(value => !value) || new Set(names).size !== names.length) {
  throw new Error("Android notification resource names are invalid or collide.");
}
function androidString(value) {
  let argument = 0;
  return value.replaceAll("\\", "\\\\").replaceAll("'", "\\'").replaceAll('"', '\\"')
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll("%@", () => `%${++argument}$s`);
}
mkdirSync(outputDirectory, {recursive: true});
for (const language of ["de", "uk"]) {
  const lines = [...keys].sort().map(key => {
    const value = strings[key]?.localizations?.[language]?.stringUnit?.value;
    if (typeof value !== "string") throw new Error(`Missing ${language} notification resource: ${key}`);
    return `    <string name="${androidPushResourceKey(key)}">${androidString(value)}</string>`;
  });
  writeFileSync(resolve(outputDirectory, `android-push-resources-${language}.xml`),
    `<?xml version="1.0" encoding="utf-8"?>\n<!-- Generated from current iOS resources; review before Android integration. -->\n<resources>\n${lines.join("\n")}\n</resources>\n`);
}
console.log(`Exported ${keys.size} notification strings per locale from the current iOS source.`);
