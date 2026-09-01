import assert from "node:assert/strict";
import test from "node:test";

import {
  buildContentPlanningSummary,
  canonicalizeURL,
} from "./contentPlanningBridgeSummary.mjs";

test("content planning summary exposes canonical sources and event identity fields", () => {
  const summary = buildContentPlanningSummary({
    id: "draft-1",
    defaultKind: undefined,
    fields: {
      kind: "event",
      state: "readyForReview",
      title: "Airport Reef Closing — One Last Dance",
      sources: [
        {url: "https://Example.org/event/?utm_source=uac#tickets", isPrimary: true},
      ],
      payload: {
        germanTitle: "Airport Reef Closing: One Last Dance",
        eventOrganizerName: "Airport Reef Innsbruck",
        venue: "Airport Reef",
        address: "Promenade 199",
        city: "Innsbruck",
        federalState: "tirol",
        startDate: "2026-09-03T16:00:00+02:00",
        endDate: "2026-09-03T22:00:00+02:00",
        additionalOccurrences: [
          {startDate: "2026-09-04T15:00:00+02:00", endDate: "2026-09-04T23:00:00+02:00"},
        ],
      },
    },
  });

  assert.equal(summary.kind, "event");
  assert.equal(summary.sourceURL, "https://Example.org/event/?utm_source=uac#tickets");
  assert.deepEqual(summary.canonicalURLs, ["https://example.org/event"]);
  assert.deepEqual(summary.occurrenceStartDates, [
    "2026-09-03T16:00:00+02:00",
    "2026-09-04T15:00:00+02:00",
  ]);
  assert.equal(summary.normalizedOrganizerName, "airport reef innsbruck");
  assert.equal(summary.normalizedPlace, "airport reef promenade 199 innsbruck");
  assert.deepEqual(summary.normalizedTitles, [
    "airport reef closing one last dance",
  ]);
});

test("content planning summary keeps live event action URLs and collection kind", () => {
  const summary = buildContentPlanningSummary({
    id: "event-1",
    defaultKind: "event",
    fields: {
      title: "Festival",
      moderationStatus: "approved",
      organizerName: "Organizer",
      externalAction: {url: "https://example.org/tickets?gclid=tracking&date=2026-09-01"},
      occurrences: [
        {startDate: "2026-09-01T18:00:00+02:00", endDate: "2026-09-01T20:00:00+02:00"},
      ],
    },
  });

  assert.equal(summary.kind, "event");
  assert.equal(summary.state, "approved");
  assert.equal(summary.canonicalURLs, undefined);
  assert.deepEqual(summary.canonicalActionURLs, ["https://example.org/tickets?date=2026-09-01"]);
  assert.equal(summary.actionCompositeKeys.length, 1);
  assert.match(summary.actionCompositeKeys[0], /eventAction/);
});

test("shared organizer and contact URLs never become standalone duplicate identities", () => {
  const sharedFields = {
    organizerName: "Shared Organizer",
    organizerURL: "https://example.org/",
    contactURL: "https://example.org/contact",
    venue: "Shared Hall",
  };
  const first = buildContentPlanningSummary({
    id: "event-1",
    defaultKind: "event",
    fields: {
      ...sharedFields,
      title: "First Event",
      startDate: "2026-09-01T18:00:00+02:00",
      endDate: "2026-09-01T20:00:00+02:00",
    },
  });
  const second = buildContentPlanningSummary({
    id: "event-2",
    defaultKind: "event",
    fields: {
      ...sharedFields,
      title: "Second Event",
      startDate: "2026-09-02T18:00:00+02:00",
      endDate: "2026-09-02T20:00:00+02:00",
    },
  });

  assert.equal(first.sourceURL, undefined);
  assert.equal(first.canonicalURLs, undefined);
  assert.deepEqual(first.canonicalContextualURLs, [
    "https://example.org/",
    "https://example.org/contact",
  ]);
  assert.deepEqual(second.canonicalContextualURLs, first.canonicalContextualURLs);
  assert.notDeepEqual(second.eventCompositeKeys, first.eventCompositeKeys);
});

test("canonical URL keeps identity query parameters and sorts them", () => {
  assert.equal(
    canonicalizeURL("https://example.org/event/?b=2&utm_medium=email&a=1#section"),
    "https://example.org/event?a=1&b=2"
  );
});
