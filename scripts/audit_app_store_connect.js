#!/usr/bin/env node
/* Read-only App Store Connect release preflight. Never prints credentials. */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const bundleId = process.argv[2] || "at.serlest.UkrainianCommunity";
const envPath = process.env.ASC_ENV_FILE || path.join(process.env.HOME || "", ".private_keys/appstoreconnect.env");

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

async function request(token, endpoint) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${endpoint}`, {
    headers: {Authorization: `Bearer ${token}`},
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    return {
      unavailable: true,
      status: response.status,
      errors: (body.errors || []).map((error) => ({code: error.code, title: error.title})),
    };
  }
  return body;
}

function attributes(resource) {
  if (!resource || resource.unavailable) return resource;
  if (Array.isArray(resource.data)) {
    return resource.data.map((item) => ({id: item.id, ...item.attributes}));
  }
  return resource.data ? {id: resource.data.id, ...resource.data.attributes} : null;
}

function reviewSummary(resource) {
  if (!resource || resource.unavailable) return resource;
  const item = resource.data;
  if (!item) return null;
  const value = item.attributes || {};
  return {
    id: item.id,
    hasContactFirstName: Boolean(value.contactFirstName),
    hasContactLastName: Boolean(value.contactLastName),
    hasContactPhone: Boolean(value.contactPhone),
    hasContactEmail: Boolean(value.contactEmail),
    demoAccountRequired: value.demoAccountRequired,
    hasDemoAccountName: Boolean(value.demoAccountName),
    hasDemoAccountPassword: Boolean(value.demoAccountPassword),
    hasReviewNotes: Boolean(value.notes),
    reviewNotesLength: typeof value.notes === "string" ? value.notes.length : 0,
  };
}

async function main() {
  const env = readEnv(envPath);
  const keyId = process.env.ASC_KEY_ID || env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID || env.ASC_ISSUER_ID;
  const keyPath = process.env.ASC_KEY_PATH || env.ASC_KEY_PATH;
  if (!keyId || !issuerId || !keyPath) throw new Error("Missing App Store Connect API credentials.");
  const token = makeJwt(keyId, issuerId, keyPath);

  const appResponse = await request(token, `/v1/apps?filter%5BbundleId%5D=${encodeURIComponent(bundleId)}&limit=1`);
  const app = appResponse.data?.[0];
  if (!app) throw new Error(`App not found for bundle ID ${bundleId}.`);

  const versionsResponse = await request(token, `/v1/apps/${app.id}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=20`);
  const versions = versionsResponse.data || [];
  const version = versions.find((item) => item.attributes?.versionString === "1.0") || versions[0];
  if (!version) throw new Error("No iOS App Store version found.");

  const [build, review, localizations, appInfos, availability, priceSchedule] = await Promise.all([
    request(token, `/v1/appStoreVersions/${version.id}/build`),
    request(token, `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`),
    request(token, `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=20`),
    request(token, `/v1/apps/${app.id}/appInfos?limit=20`),
    request(token, `/v1/apps/${app.id}/appAvailabilityV2`),
    request(token, `/v1/apps/${app.id}/appPriceSchedule`),
  ]);

  const localizationRows = [];
  for (const localization of localizations.data || []) {
    const sets = await request(token, `/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?limit=50`);
    const screenshotSets = [];
    for (const set of sets.data || []) {
      const screenshots = await request(token, `/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`);
      screenshotSets.push({
        displayType: set.attributes?.screenshotDisplayType,
        screenshotCount: screenshots.data?.length || 0,
      });
    }
    localizationRows.push({locale: localization.attributes?.locale, screenshotSets});
  }

  const infoRows = [];
  for (const info of appInfos.data || []) {
    const [primaryCategory, secondaryCategory, ageRating] = await Promise.all([
      request(token, `/v1/appInfos/${info.id}/primaryCategory`),
      request(token, `/v1/appInfos/${info.id}/secondaryCategory`),
      request(token, `/v1/appInfos/${info.id}/ageRatingDeclaration`),
    ]);
    infoRows.push({
      state: info.attributes?.appStoreState,
      primaryCategory: attributes(primaryCategory),
      secondaryCategory: attributes(secondaryCategory),
      ageRating: attributes(ageRating),
    });
  }

  let priceSummary = attributes(priceSchedule);
  if (priceSchedule.data?.id) {
    const [baseTerritory, manualPrices] = await Promise.all([
      request(token, `/v1/appPriceSchedules/${priceSchedule.data.id}/baseTerritory`),
      request(token, `/v1/appPriceSchedules/${priceSchedule.data.id}/manualPrices?include=appPricePoint,territory&limit=200`),
    ]);
    const included = new Map((manualPrices.included || []).map((item) => [item.id, item]));
    priceSummary = {
      id: priceSchedule.data.id,
      baseTerritory: attributes(baseTerritory),
      manualPrices: (manualPrices.data || []).map((price) => {
        const pricePointId = price.relationships?.appPricePoint?.data?.id;
        const pricePoint = included.get(pricePointId);
        return {
          startDate: price.attributes?.startDate,
          endDate: price.attributes?.endDate,
          customerPrice: pricePoint?.attributes?.customerPrice,
          territoryId: price.relationships?.territory?.data?.id,
        };
      }),
    };
  }

  const result = {
    checkedAt: new Date().toISOString(),
    app: {id: app.id, bundleId: app.attributes?.bundleId, name: app.attributes?.name, contentRightsDeclaration: app.attributes?.contentRightsDeclaration},
    version: {id: version.id, ...version.attributes},
    selectedBuild: attributes(build),
    reviewDetail: reviewSummary(review),
    localizations: localizationRows,
    appInfos: infoRows,
    availability: attributes(availability),
    priceSchedule: priceSummary,
    note: "The App Privacy questionnaire is not exposed by the public App Store Connect API and requires authenticated UI verification.",
  };
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
