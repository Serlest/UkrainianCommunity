import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  parseAnalyticsRequest,
  sanitizeAnalyticsEvent,
} from "./trackAnalyticsEvent";

test("accepts only the canonical analytics request envelope", () => {
  assert.equal(parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
  }).name, "news_view");

  assert.throws(() => parseAnalyticsRequest({
    eventName: "news_view",
    parameters: {content_id: "news-1"},
  }));
  assert.throws(() => parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
    actorUserId: "forged-user",
  }));
});

test("uses canonical content metadata instead of client supplied values", () => {
  const request = parseAnalyticsRequest({
    name: "news_view",
    parameters: {
      content_id: "news-1",
      content_type: "news",
      content_title: "Forged title",
      organization_id: "forged-organization",
      organization_name: "Forged organization",
      category: "forged",
      federal_state: "tirol",
      region_scope: "federalState",
    },
  });

  const event = sanitizeAnalyticsEvent(request, {
    contentID: "news-1",
    contentType: "news",
    title: "Canonical title",
    organizationID: "canonical-organization",
    organizationName: "Canonical organization",
    category: "community",
    federalState: "wien",
    regionScope: "federalState",
  });

  assert.equal(event.title, "Canonical title");
  assert.equal(event.organizationID, "canonical-organization");
  assert.equal(event.organizationName, "Canonical organization");
  assert.equal(event.category, "community");
  assert.equal(event.federalState, "wien");
});

test("rejects mismatched canonical content identity", () => {
  const request = parseAnalyticsRequest({
    name: "event_view",
    parameters: {content_id: "event-1"},
  });

  assert.throws(() => sanitizeAnalyticsEvent(request, {
    contentID: "different-event",
    contentType: "event",
    title: "Canonical event",
  }));
});
