import {strict as assert} from "node:assert";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  analyticsConsentDisclosureVersion,
  analyticsConsentPrivacyVersion,
  analyticsConsentPurposeVersion,
  analyticsConsentReceiptID,
  consentPrivacyVersion,
  isCurrentAnalyticsConsent,
  parseAnalyticsConsentMutation,
} from "./analyticsConsent";

const consentID = "123e4567-e89b-42d3-a456-426614174000";

test("analytics consent mutation accepts one versioned grant or withdrawal", () => {
  assert.deepEqual(parseAnalyticsConsentMutation({
    enabled: true,
    consentID,
    locale: "de",
    appVersion: "1.0.26",
  }), {
    enabled: true,
    consentID,
    locale: "de",
    appVersion: "1.0.26",
  });
  assert.throws(() => parseAnalyticsConsentMutation({enabled: true, consentID: "bad", locale: "de"}));
  assert.throws(() => parseAnalyticsConsentMutation({enabled: true, consentID, locale: "en"}));
  assert.throws(() => parseAnalyticsConsentMutation({enabled: true, consentID, locale: "de", extra: true}));
});

test("current consent requires the exact ID and release contract", () => {
  const data = {
    enabled: true,
    consentID,
    purposeVersion: analyticsConsentPurposeVersion,
    privacyVersion: analyticsConsentPrivacyVersion,
    disclosureVersion: analyticsConsentDisclosureVersion,
  };
  assert.equal(isCurrentAnalyticsConsent(data, consentID), true);
  assert.equal(isCurrentAnalyticsConsent({...data, enabled: false}, consentID), false);
  assert.equal(isCurrentAnalyticsConsent(data, "223e4567-e89b-42d3-a456-426614174000"), false);
  assert.equal(isCurrentAnalyticsConsent({...data, privacyVersion: "old"}, consentID), false);
});

test("consent receipt identifiers are stable and do not expose principal or UUID", () => {
  const receiptID = analyticsConsentReceiptID("private-user", consentID);
  assert.match(receiptID, /^[0-9a-f]{64}$/);
  assert.equal(receiptID.includes("private-user"), false);
  assert.equal(receiptID.includes(consentID), false);
});


test("server receipt versions match the current iOS disclosure contract", () => {
  const root = resolve(__dirname, "../../../UkrainianCommunity/Services");
  const auth = readFileSync(resolve(root, "Auth/AuthService.swift"), "utf8");
  const consent = readFileSync(resolve(root, "Analytics/AnalyticsConsentService.swift"), "utf8");
  assert.equal(auth.match(/currentPrivacyVersion = "([^"]+)"/)?.[1], analyticsConsentPrivacyVersion);
  assert.equal(consent.match(/disclosureVersion = "([^"]+)"/)?.[1], analyticsConsentDisclosureVersion);
});


test("privacy correction accepts both released and new explicit consent versions without relabeling", () => {
  for (const privacyVersion of ["2026.12", "2026.13"]) {
    for (const enabled of [true, false]) {
      const input = parseAnalyticsConsentMutation({
        enabled, consentID, locale: "uk", appVersion: "1.0.3",
        privacyVersion, disclosureVersion: analyticsConsentDisclosureVersion,
      });
      assert.equal(consentPrivacyVersion(input), privacyVersion);
    }
    assert.equal(isCurrentAnalyticsConsent({
      enabled: true, consentID, privacyVersion,
      disclosureVersion: analyticsConsentDisclosureVersion,
      purposeVersion: analyticsConsentPurposeVersion,
    }, consentID), true);
  }
  const input = {enabled: true, consentID, locale: "de" as const};
  assert.equal(consentPrivacyVersion({...input, appVersion: "1.0.1"}), "2026.12");
  assert.equal(consentPrivacyVersion({...input, appVersion: "1.0.2"}), "2026.12");
  // Never infer evidence for the new release from its app version alone.
  assert.throws(() => consentPrivacyVersion({...input, appVersion: "1.0.3"}));
  for (const versions of [
    {privacyVersion: "2026.14", disclosureVersion: analyticsConsentDisclosureVersion},
    {privacyVersion: "2026.13", disclosureVersion: "unknown"},
    {privacyVersion: "2026.13"},
    {disclosureVersion: analyticsConsentDisclosureVersion},
  ]) {
    assert.throws(() => parseAnalyticsConsentMutation({...input, ...versions}));
  }
});
