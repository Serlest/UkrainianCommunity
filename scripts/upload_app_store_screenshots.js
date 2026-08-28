#!/usr/bin/env node
/* Upload a localized App Store screenshot set through the official ASC API. */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const [locale, directory, displayType = "APP_IPHONE_67"] = process.argv.slice(2);
if (!locale || !directory) {
  console.error("Usage: upload_app_store_screenshots.js <locale> <directory> [displayType]");
  process.exit(2);
}

const envPath = process.env.ASC_ENV_FILE || path.join(process.env.HOME || "", ".private_keys/appstoreconnect.env");
const bundleId = process.env.ASC_BUNDLE_ID || "at.serlest.UkrainianCommunity";

function readEnv(file) {
  const values = {};
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.trim().match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (match) values[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
  }
  return values;
}

function base64url(input) {
  return Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function makeJwt(keyId, issuerId, keyPath) {
  const now = Math.floor(Date.now() / 1000);
  const header = {alg: "ES256", kid: keyId, typ: "JWT"};
  const payload = {iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1"};
  const input = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = crypto.sign("sha256", Buffer.from(input), {
    key: fs.readFileSync(keyPath, "utf8"),
    dsaEncoding: "ieee-p1363",
  });
  return `${input}.${base64url(signature)}`;
}

async function api(token, endpoint, {method = "GET", body} = {}) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${endpoint}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? {"Content-Type": "application/json"} : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const details = (payload.errors || []).map((error) => `${error.code}: ${error.title} ${error.detail || ""}`.trim()).join("; ");
    throw new Error(`${method} ${endpoint} failed (${response.status}): ${details}`);
  }
  return payload;
}

async function uploadOperation(operation, file) {
  const headers = Object.fromEntries((operation.requestHeaders || []).map(({name, value}) => [name, value]));
  const start = operation.offset || 0;
  const length = operation.length || file.length;
  const response = await fetch(operation.url, {
    method: operation.method || "PUT",
    headers,
    body: file.subarray(start, start + length),
  });
  if (!response.ok) throw new Error(`Asset upload failed (${response.status}) for offset ${start}.`);
}

async function waitUntilProcessed(token, screenshotId) {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const current = await api(token, `/v1/appScreenshots/${screenshotId}`);
    const state = current.data?.attributes?.assetDeliveryState;
    if (state?.errors?.length) throw new Error(`Screenshot processing failed: ${JSON.stringify(state.errors)}`);
    if (state?.state === "COMPLETE") return;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`Timed out while processing screenshot ${screenshotId}.`);
}

async function main() {
  const env = readEnv(envPath);
  const keyId = process.env.ASC_KEY_ID || env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID || env.ASC_ISSUER_ID;
  const keyPath = process.env.ASC_KEY_PATH || env.ASC_KEY_PATH;
  if (!keyId || !issuerId || !keyPath) throw new Error("Missing App Store Connect API credentials.");
  const token = makeJwt(keyId, issuerId, keyPath);

  const files = fs.readdirSync(directory)
    .filter((name) => name.toLowerCase().endsWith(".png"))
    .sort()
    .map((name) => path.resolve(directory, name));
  if (!files.length) throw new Error(`No PNG files found in ${directory}.`);
  if (files.length > 10) throw new Error("App Store Connect accepts at most 10 screenshots per set.");

  const app = (await api(token, `/v1/apps?filter%5BbundleId%5D=${encodeURIComponent(bundleId)}&limit=1`)).data?.[0];
  if (!app) throw new Error(`App not found for bundle ID ${bundleId}.`);
  const versions = (await api(token, `/v1/apps/${app.id}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=20`)).data || [];
  const version = versions.find((item) => item.attributes?.versionString === "1.0") || versions[0];
  if (!version) throw new Error("No iOS App Store version found.");
  const localizations = (await api(token, `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=20`)).data || [];
  const localization = localizations.find((item) => item.attributes?.locale === locale);
  if (!localization) throw new Error(`Localization ${locale} was not found.`);

  let sets = (await api(token, `/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?limit=50`)).data || [];
  let set = sets.find((item) => item.attributes?.screenshotDisplayType === displayType);
  if (!set) {
    set = (await api(token, "/v1/appScreenshotSets", {
      method: "POST",
      body: {
        data: {
          type: "appScreenshotSets",
          attributes: {screenshotDisplayType: displayType},
          relationships: {
            appStoreVersionLocalization: {
              data: {type: "appStoreVersionLocalizations", id: localization.id},
            },
          },
        },
      },
    })).data;
  }

  const existing = (await api(token, `/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`)).data || [];
  for (const screenshot of existing) {
    await api(token, `/v1/appScreenshots/${screenshot.id}`, {method: "DELETE"});
  }

  for (const filePath of files) {
    const file = fs.readFileSync(filePath);
    const reserved = await api(token, "/v1/appScreenshots", {
      method: "POST",
      body: {
        data: {
          type: "appScreenshots",
          attributes: {fileName: path.basename(filePath), fileSize: file.length},
          relationships: {
            appScreenshotSet: {data: {type: "appScreenshotSets", id: set.id}},
          },
        },
      },
    });
    const screenshotId = reserved.data.id;
    for (const operation of reserved.data.attributes.uploadOperations || []) {
      await uploadOperation(operation, file);
    }
    await api(token, `/v1/appScreenshots/${screenshotId}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appScreenshots",
          id: screenshotId,
          attributes: {
            uploaded: true,
            sourceFileChecksum: crypto.createHash("md5").update(file).digest("hex"),
          },
        },
      },
    });
    await waitUntilProcessed(token, screenshotId);
    console.log(`Uploaded ${path.basename(filePath)}`);
  }

  const verified = await api(token, `/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`);
  console.log(JSON.stringify({locale, displayType, count: verified.data?.length || 0, files: verified.data?.map((item) => item.attributes?.fileName)}, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
