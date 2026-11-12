# Glucose readings in the Daily JSON export, v1 (#469)

Status: **owner-decided 11 November 2026 (D1 to D8, section 11) and 12 November 2026 (D9); implemented in the PR for #469.** No device action, personal-data transfer or release is authorised by this document; the device acceptance in section 12 is the owner's and is outstanding.

Architecture gate: **PASS WITH CHANGES**, 11 November 2026 (read-only `architecture-gate` review against the code at `03510ae`). Its eight changes are folded in below: whole-second timestamp text, schema 9 layered on schema 8 only, the admission rules, the toggle's own setter and preference, the service and port rows, no duplicate window, the wider document amendments and ten further contract tests.

## 1. Outcome and boundary

The health Daily JSON export can carry every glucose reading visible in Apple Health for the selected day, each with its own time, value and source, so a consumer can place readings on a timeline beside workouts and meals. The existing daily and hourly glucose statistics cannot show when a rise began or peaked.

This is an export-only detail. The Health screen, Copy all and the weekly report are unchanged, which this specification states as the exception to "show every metric consistently". Developer tools gains the comparison rows in section 8.

## 2. What exists today

- `today.glucose` carries daily average / minimum / maximum plus hourly statistics with explicit missing-hour states (`DailyGlucoseData`, `HourlyGlucoseData` in `WeeklyHealthReport/Models/DailyHealthExport.swift`).
- Every glucose read is a statistics query (`fetchGlucoseStatistics`, `fetchDailyBloodGlucose` in `WeeklyHealthReport/HealthKit/HealthKitClient.swift`). There is no per-sample glucose query.
- [daily-export-contract.md](daily-export-contract.md) requires hourly values to come from HealthKit statistics, not from merging overlapping sources by hand. That rule stays in force for statistics.
- The runtime envelope is schema 8 when any workout carries detail (always enrichment version 3, because heart-rate readings are always requested) and schema 7 on a day with no workout detail. Drive admits 1, 2, 3, 6, 7 and 8 (`DailyDriveExportCoordinator`).
- Envelope timestamps are whole-second text with the reporting zone's offset (`ExportDateText.timestamp`, `yyyy-MM-dd'T'HH:mm:ssXXXXX`). Milliseconds and numeric dates exist only for native `Date` values inside workout detail.
- The only per-export choice on the Export screen is the Food log toggle. It selects a separate file and does not clear the health preview, so it is not a model for this choice.

## 3. Data shape (Apple documentation)

- `bloodGlucose` is a discrete quantity type in mass / volume units, stored as mg/dL or mmol/L depending on region. The app already converts at the query boundary with `HKUnitMolarMassBloodGlucose`.
- A sample made with an initialiser has `count == 1`. A sample made with `HKQuantitySeriesSampleBuilder` may have `count > 1`, and its quantity is then not one reading.
- A source may attach `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`. HealthKit replaces a stored object only when a new object with the same identifier has a greater version. Apple does not document the equal or lower case.
- HealthKit does not disclose read denial. An empty successful read means no visible data or no access.

Sources: [bloodGlucose](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bloodglucose), [HKQuantitySample.count](https://developer.apple.com/documentation/healthkit/hkquantitysample/count), [HKMetadataKeySyncIdentifier](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier), [HKSampleQueryDescriptor](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor). Read on 11 November 2026.

### Owner's device observation, 11 November 2026

Seen in the Health app on one iPhone, not validated by this app: point samples with a single timestamp at whole-second display precision; 5-minute cadence (288 a day); the newest reading about three hours behind the clock; sync identifier and version present; one sample already listed later showed a newer "Date Added to Health", so the source appears to re-save samples. This contract names no sensor vendor and depends on none of these observations being true.

## 4. Architecture gate

| Responsibility | Home |
|---|---|
| Read visible samples for one interval, convert units, map to plain values | `HealthKitClient`, inside the existing `fetchDailyHealthExportInputs` call so the read keeps its daily-export diagnostics labelling. A flag on that call requests the readings; the result is a new field on `DailyHealthExportInputs`. Each plain value carries time, end time, sample count, converted value, source name, source bundle identifier and an internal identifier, unfiltered. No HealthKit type crosses the port. |
| Pass the choice through and freeze it with the window | `DailyHealthExportService.refresh` and the `DailyHealthExportDataProviding` port (signature change; the three test fakes follow) |
| Validate, order, group by source, apply the bound, decide the state | A pure model beside `GlucoseSummary` in `WeeklyHealthReport/Models`, with no HealthKit, SwiftUI or clock dependency. It owns the bound; the client receives it as the query limit. |
| Place the block in the envelope and choose the schema version | `DailyHealthExport.make` (new parameter) and `DailyHealthExportSerializer`. The new property joins the explicit `CodingKeys` of `DailyHealthMetrics`, or it would be dropped silently. |
| Admit schema 9 and validate the block at strict admission | `DailyDriveExportCoordinator`, existing exact-byte and `historical-v2` rules |
| The choice, its preference, the Included line, disclosure copy, Developer tools rows | `DailyDriveSessionController` and presentation, reading the prepared envelope only |

Dependency direction is unchanged: presentation and infrastructure depend on the pure models. No new protocol, provider abstraction or package target is needed, so `check-boundaries.sh` is unaffected. Closed invariants: read-only HealthKit; unknown is never zero; no interpolation, resampling or deduplication; statistics stay statistics; earlier schema bytes are unchanged. No new extension axis is opened. Contract tests are listed in section 9.

## 5. Query and time semantics

- **Window.** The selected export day under the daily contract: local midnight to the next local midnight, or to the frozen cutoff for today, start included and end excluded. A reading belongs to the day containing its start instant. DST days of 23 or 25 hours need no special case, and timestamps keep their offsets so a repeated local hour stays distinguishable.
- **Query.** One `HKSampleQueryDescriptor` for `bloodGlucose` with a strict-start-date predicate over that window, sorted by start date, limited to the bound plus one so excess is detected without reading further.
- **No source filter.** Every visible source is read. Readings are grouped by source and never merged into one series (section 6).
- **Units.** Converted to mmol/L at the query boundary.
- **Supported sample shape.** `count == 1` and start equal to end. A sample with `count > 1` or a duration is not a point reading; v1 does not expand or flatten it (decision D6).
- **A day of no length.** A refresh at exactly local midnight has an empty window; like every other daily metric it is not queried, and the block reads `no_data_or_access`.
- **Snapshot meaning.** The block lists the records visible at the cutoff. It is not a statement that the day is complete: a source may deliver hours late or re-save records. Re-exporting the day replaces the file under the existing replacement rules.
- **Trailing gap.** The time between `last_reading_time` and `data_as_of` is never labelled. It may be a sensor gap or readings not yet delivered; the export cannot tell and does not claim either.
- **Statistics are independent.** Daily and hourly statistics are still queried as they are today. Nothing is derived from the readings, and the contract does not promise that statistics and readings reconcile when sources overlap.

## 6. JSON (schema 9)

Schema 9 is emitted only when the Glucose readings choice is on. With the choice off the app emits exactly the bytes it emits today.

`today.glucose_readings`, a sibling of `today.glucose` so its state does not depend on the statistics being available:

```json
"glucose_readings": {
  "readings_version": 1,
  "state": "available",
  "unit": "mmol/L",
  "count": 3,
  "last_reading_time": "2026-01-10T08:10:00Z",
  "series": [
    {
      "source_name": "Example Sensor",
      "source_bundle_identifier": "com.example.sensor",
      "count": 3,
      "readings": [
        { "time": "2026-01-10T08:00:00Z", "value": 5.2 },
        { "time": "2026-01-10T08:05:00Z", "value": 5.4 },
        { "time": "2026-01-10T08:10:00Z", "value": 5.3 }
      ]
    }
  ]
}
```

- **Timestamps** are text in the envelope's existing format: whole seconds with the reporting time zone's offset, rendered in `make` like `data_as_of`. As elsewhere in the envelope, a zero offset is written `Z`. No native `Date` is added, so schema 8's numeric date rule does not apply to this block. A sub-second part is not exported; a test pins that it is truncated, not rounded into the next second. This is the owner's decision D9, taken knowing that the stored precision was never checked.
- **Window.** The block has no window of its own. The interval queried is the envelope's `day_window`, which for today already ends at the cutoff.
- **`count` and `last_reading_time`** at the top of the block are facts about the records listed, across all sources: how many there are and the latest time among them. They are not a coverage or completeness measure.
- **`series`** has one element per source, ordered by bundle identifier then name. Readings inside a series are ordered by native time, then value, then an internal object identifier that is never exported. Two visible records with the same source and time are both kept. Because text is whole seconds, two readings in one rendered second may appear with descending values; admission therefore checks non-decreasing rendered time only.
- **`value`** is a finite, positive JSON number: the converted mmol/L value, unrounded, as the existing glucose statistics are exported (decision D2). The example above uses short values for readability only.
- **Not exported:** HealthKit object identifiers, sync identifiers and versions, meal-time and user-entered metadata, device details.

States:

| `state` | Meaning | Fields present |
|---|---|---|
| `available` | Every visible sample in the window was read and validated | all |
| `no_data_or_access` | The read succeeded and returned nothing. Not zero, and not proof of denial | `readings_version`, `state`, `unit` |
| `limit_exceeded` | More samples than the bound. No partial list is exported | same three |
| `invalid_evidence` | A sample had an unsupported shape, a non-finite or non-positive value, or no source identity. No partial list is exported | same three |

A query error or cancellation blocks the export, as for every other metric.

**Bound:** 2,000 samples per day (decision D3). A 5-minute source produces 288.

**Version layering (decision D1).** Schema 9 is schema 8 plus this block. Workout detail, when present, must be enrichment version 3 and keeps schema 8's numeric native dates; the builder fails closed otherwise. A day with no workout detail has no native `Date` at all, so its schema 9 bytes differ from today's schema 7 bytes only by `schema_version` and the block. The serializer treats 9 as it treats 8. Schemas 3, 6, 7 and 8 keep their meaning and bytes.

**Admission of schema 9.** The block is required: a schema 9 file without it, with enrichment version 1 or 2, or with either food field is rejected. The block must be self-consistent: known `readings_version` and `state`; `unit` exactly `mmol/L`; only the fields its state allows; each series count equal to its list length and the top count equal to their sum; at most 2,000 readings; series unique and in order; every reading inside `day_window` with a finite positive value and whole-second time text, in the reporting zone's own offset for that instant, in non-decreasing order (a reading may equal the rendered end only when the day ends at the cutoff, because the cutoff is truncated to a whole second); nonempty source name and bundle identifier; `last_reading_time` equal to the latest reading. A `glucose_readings` key in any earlier schema fails admission, as it does today through exact-byte re-encoding.

## 7. Export screen

- A **Glucose readings** toggle beside Food log, off by default. It has its own setter on the session controller and its own stored preference, separate from the Food log preference. Changing it clears the prepared preview and the last export outcome and requires a fresh refresh and review, because it changes the health file's bytes. A change while the session is busy is ignored. A preview prepared before a change can never be exported.
- Disclosure under the toggle: "Each glucose reading Apple Health shows for this day, with its time and source. Readings can reach Apple Health some hours late, so export the day again to include them. Gaps are never filled in."
- The Included list gains one line for the block: the reading count when available, otherwise the state in plain words ("No visible data or no access", "Too many readings to include", "Readings could not be included"). The block is not a sixteenth metric and does not change the metric count in [daily-export-included-summary-v1.md](daily-export-included-summary-v1.md).
- View exact file shows the block like any other part of the payload.

## 8. Developer tools

For the selected export day, per source: reading count, first and last reading time, and the block's state. This is what the owner compares with Health's "All Recorded Data" list. No readings are logged.

## 9. Tests (synthetic fixtures only)

- **Pure model:** ordering and grouping; two sources with overlapping times kept apart; same source and time kept twice; gaps left as gaps; empty read; bound reached exactly and exceeded by one; a series sample and a sample with a duration each give `invalid_evidence`; non-finite and non-positive values; window edges (start included, end and cutoff excluded); 23-hour and 25-hour days; a reading in a repeated local hour; midnight capture.
- **Query boundary:** choice off makes no readings request and choice on carries the frozen window to the port (provider spy). The HealthKit query itself (no source predicate, a limit of the bound plus one, mg/dL converted to mmol/L) has no unit test, because the test suite never opens a HealthKit store; it is covered by code review and by the device comparison in section 12.
- **Builder and serializer:** choice off gives byte-identical output to the current golden snapshots; choice on gives schema 9 with the block; `today.glucose` bytes are identical with the choice on and off; a day without workout detail differs from its schema 7 bytes only by `schema_version` and the block; schema 8's sub-millisecond workout precision test also runs for 9; each non-available state omits the list; sub-second truncation of reading times is pinned.
- **Admission:** Drive admits schema 9; schema 9 without the block, with enrichment 1 or 2, or with food fields is rejected; a forged block in schemas 3, 6, 7 or 8 is rejected; each block forgery is rejected (count mismatches, unsorted or duplicate series, a reading outside the window, wrong `last_reading_time`, state and field mismatch, wrong unit or version, more than 2,000, empty source, non-positive value, fractional time text); two readings in one rendered second, in native order, pass; a schema 9 file re-encodes to the same bytes; `historical-v2` ordering applies.
- **View model and UI:** toggling clears the preview and last outcome; toggling while busy is ignored; a preview made before a toggle cannot be exported; the preference persists; the Included line for each state; the metric denominator stays 15; the disclosure copy; VoiceOver label and 44 pt target for the toggle.
- **Gates:** the full list in `AGENTS.md`. Search evaluation is not affected.

## 10. Egress amendment (owner-approved 11 November 2026, E3 amended the same day)

The owner approved terms E1 to E4 on 11 November 2026 ("Approve E1 to E4"). They take effect from the implementation PR that ships the behaviour and amends the documents named in E4; until then no build sends a glucose reading.

Terms:

- **E1** The destination, scope and trigger are unchanged: Google Drive (`drive.file`), only when the user chooses Export, only the exact reviewed bytes.
- **E2** The Daily JSON may additionally contain each visible glucose reading for the selected day with its time, value, source name and source bundle identifier, only while the Glucose readings choice is on.
- **E3** Off by default. Readings are part of the Daily JSON wherever the user takes that file: the Drive export, and the existing View exact file with its Copy JSON, which shows the exact text on screen and copies it to this iPhone's clipboard only, where the entry expires after ten minutes. Developer tools shows each source's name and bundle identifier, the reading count and the first and last reading time of the prepared file, and never a reading value. No reading leaves by any other route, and nothing here authorises background or automatic export. *Amended by the owner on 11 November 2026 ("amend wording"): the wording first approved, "No reading leaves through any other route", overlooked Copy JSON and the Developer tools rows, which the invariant review found.*
- **E4** `docs/privacy-and-egress.md` (the HealthKit bullet and the Google Drive row) and `docs/privacy-policy.txt` are amended in the implementation PR, so the documents change in the same release as the behaviour. The same PR adds a schema 9 amendment to [daily-export-contract.md](daily-export-contract.md) (envelope versions, historical ordering and the glucose row) and the "not counted as a metric" entry to [daily-export-included-summary-v1.md](daily-export-included-summary-v1.md). The egress table's Clipboard row keeps its existing wording, which a test pins word for word and which does not mention Copy JSON; the Copy JSON route is stated in the HealthKit bullet of the same document.

## 11. Owner decisions

| | Decision | Recommendation |
|---|---|---|
| D1 | Schema layering | **Accepted by the owner, 11 November 2026:** schema 9 is schema 8 plus the block, as in section 6 |
| D2 | Value precision | **Decided by the owner, 11 November 2026: unrounded**, matching the existing statistics and "rounded only for display". Rounding to two decimals was the alternative and was not chosen |
| D3 | Daily bound | **Accepted by the owner, 11 November 2026:** 2,000 |
| D4 | Shape | **Accepted by the owner, 11 November 2026:** one series per source with `{ time, value }` readings, as in section 6 |
| D5 | Default | **Decided by the owner, 11 November 2026:** off, with its own remembered preference |
| D6 | Series samples and samples with a duration | **Accepted by the owner, 11 November 2026:** fail closed as `invalid_evidence` in v1; expand them only if a real source needs it |
| D7 | Egress terms E1 to E4 | **Approved by the owner, 11 November 2026** |
| D8 | Priority | **Decided by the owner, 11 November 2026:** start now, alongside the two features in progress |
| D9 | Reading time precision | **Decided by the owner, 12 November 2026: whole seconds.** Issue #469 asked for a check in code of whether stored timestamps carry a sub-second part, with text used only if nothing is lost. No such check was made: the only observation is the Health app's whole-second display, which does not show the stored value. The owner keeps whole-second text as in section 6, so a sub-second part, if a source ever stores one, is truncated and not exported. Exporting milliseconds when present was the alternative and was not chosen |

## 12. Device acceptance (owner)

Simulator runs prove software behaviour only. On the iPhone, for one complete past day and for today: compare the Developer tools count, first and last time and source with Health's "All Recorded Data"; confirm a re-export on the following morning contains the evening readings; confirm the exact file in Drive matches the preview. Report the build and the dates compared.

## 13. Out of scope

Charts or any in-app timeline; medical interpretation, targets, time in range or attribution to foods or activities; readings for context days; any change to the food ledger or the food daily export (meal timing uses the existing When field as recorded); background or automatic export; a backfill beyond the seven-day export window.
