import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  analyticsConsentDisclosureVersion,
  analyticsConsentPrivacyVersion,
  analyticsConsentPurposeVersion,
  analyticsConsentReceiptID,
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
