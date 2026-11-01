# Advent 2026 remote scene package

Prepared and atomically published to the owner library and public presentation on 2026-11-01, per operator request. No application-source change, binary upload, or App Review change.

All intervals use Europe/Vienna (CET, UTC+01 during this schedule), inclusive start and exclusive end.

| Scene | Local start | Local end |
| --- | --- | --- |
| Advent 1 | 2026-11-29 00:00 | 2026-11-30 00:00 |
| Advent 2 | 2026-12-06 00:00 | 2026-12-07 00:00 |
| Advent 3 | 2026-12-13 00:00 | 2026-12-14 00:00 |
| Advent 4 | 2026-12-20 00:00 | 2026-12-21 00:00 |
| Christmas fallback | 2026-11-29 00:00 | 2026-12-26 00:00 |
| Existing New Year | 2026-12-26 00:00 | 2027-01-02 00:00 |

Advent priority 80 takes precedence over Christmas priority 20. Only one scene is selected; elements are not merged. Christmas intentionally covers the complete window as fallback. Existing management conflict guidance may flag these intentional overlaps. Manual override is absent. Halloween and GTA records are byte-equivalent to the prior decoded documents. Other original records were retained, not deleted.

The four generated transparent PNG wreaths were visually inspected for four total candles and one/two/three/four lit candles. Final imported PNGs are 96px maximum side, 14–18 KB each. A wreath replaces only the brand slot; hanging bauble and Santa flight are omitted on Advent days. Existing winter pine/snow/navigation elements remain. Wreath artwork is static: no claim of independently animated flames. Actual in-app small-size, light/dark, orientation and physical-device visual acceptance remain pending.

Both complete JSON packages are less than 100 KB when serialized compactly (limit 240,000), nine themes (limit twelve). Actual current Swift SeasonalLibrary.decode/validated and active selection logic passed 370 assertions across all five sections at start−1s/start/start+1s/midday/end−1s/end/end+1s and Christmas-to-New-Year boundaries. Executed as a macOS command-line validation using unchanged SeasonalTheme.swift and SeasonalSceneSlots.swift with presentation-only UIColor/SeasonalText shims; this is model validation, not an iOS UI test. An initial test incorrectly expected Christmas before its first scheduled start; corrected expectation to no scene and reran successfully.

Published via one Firestore commit with update-time preconditions for both documents; exact payload and revision readback succeeded. `published-readback.json` contains the receipt. Original server documents are retained privately in ignored build/advent2026/ as rollback evidence. Existing owner updatedBy values were retained; this document records the authorized Codex operation.

These are fixed dates for 2026, not annual repeats. Future Advent Sundays must be recalculated; Christmas/New Year annual repeat is disabled for these dated seasonal intervals. Active app schedule refresh checks once per second; returning/reopening refreshes selection. A client must first receive the published package, and its personal seasonal-effects preference still applies.

Sources:
- https://evang-wien.at/event/1156 — first Advent 2026: Nov 29 00:00 to Nov 30 00:00.
- https://katholisch-thueringen.de/glaube/kirchenjahr/advent — liturgical start at first Vespers on the preceding evening; this app deliberately uses the operator's full civil Sunday, not a universal liturgical clock time.

Operator date clarification: both Halloween copies end Nov 2 00:00; GTA starts at that exact instant and ends Nov 20 00:00; New Year ends Jan 2 00:00. Thus Nov 20–28 has no active scheduled scene. Both documents updated atomically with fresh preconditions and exact readback.
