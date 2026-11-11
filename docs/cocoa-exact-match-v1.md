# Cocoa exact match v1 (#462, amends #382 and #384)

Status: owner decisions 1 to 3 taken, 11 November 2026. Architecture gate PASS WITH CHANGES (11 November 2026); all five findings applied below (see Gate record).

Amends: [`cocoa-aware-search-v1.md`](cocoa-aware-search-v1.md) (rule 3 screen grouping, #391) and [`ciqual-2025-admission-v1.md`](ciqual-2025-admission-v1.md) section 4.1 (`cocoa-percent-policy-v2`). Evidence: the owner's device check of TestFlight 0.3.0 (30) on 11 November 2026.

## Problem

On the device, "dark chocolate 90%" and "dark chocolate 95%" both list about twenty bundled reference rows, none of them at the requested percentage, and only then, under "Added from online database", the one product that is what the user searched for:

- **90%:** Godiva "90% Cocoa Dark Chocolate" (Open Food Facts 5000168211954) reads as `90% cocoa` but is the last result, about three screens down.
- **95%:** TOPS "95% Dark Chocolate" (Open Food Facts 6253348102156) is also last, and its row says "Cocoa % not stated" although its name states 95%. `cocoa-percent-policy-v2` reads a percentage only when it is directly followed by "cocoa" or "cacao", so "95% Dark Chocolate" gives no band.

Both behaviours follow the current contracts: online rows are their own section after the bundled sections (phase 3 search), and the band reader is deliberately narrow. Neither is a regression. Together they put the best answer last, and for TOPS hide that it is one.

Out of scope: fibre and other nutrients an online product does not list (Godiva's record has no fibre value; the app correctly shows it as not stated). A labelled estimate for those is a separate, larger change.

## Proposed rules

### 1. `cocoa-percent-policy-v3`: "N% dark chocolate" in a product name

v3 adds one phrase, read by a new **display reading** only. The v2 band reader, `CocoaPercentPolicy.band`, is unchanged, so ranking, Open Food Facts discovery order, admission, label pre-fill and estimate compatibility read exactly what they read today.

1. **Phrase.** In the **name only** (not the description or variant), take the primary name: the text before the first comma, lower-cased, trimmed, with one trailing "bar" or "block" removed. When the primary name is exactly `N% dark chocolate` or `dark chocolate N%` (any spacing around `%`, N from 0 to 100), it reads as the point band `[N, N]`.
2. **Narrow on purpose.** The whole primary name must be the phrase, so "Digestive biscuits with 70% dark chocolate", "Almonds in 70% dark chocolate" and "70% dark chocolate chips" give no band from this rule. Brand or extra words in the primary name also give no band; they stay as they are today.
3. **Display reading.** `CocoaPercentPolicy.displayBand(_:)` returns the v2 band when v2 reads one (a declared band, the 100% estimate, an open-ended band or a blend). Only when v2 reads nothing, the row's name is the phrase, and the description or variant states no cocoa percentage of its own (no "N% cocoa" or "N% cacao"), it returns `[N, N]`. "90% Cocoa Dark Chocolate" already reads `[90, 90]` under v2 and is unchanged.
4. **Who reads it.** Only the Search row caution and detail note (`CocoaPercentPolicy.caution` and `note`) and rule 2's exact online section. Not the composite or per-source tier keys (`CompositeGenericFoodSearch`, CoFID, USDA, Ciqual searchers), not `OFFHTTPSearchTransport`'s explicit-hit order, not `admits` or `isCocoaMatch`, not `prefillBand(text:)`, `LabelEstimateCompatibility.prefill(name:)` or `isCompatible`. So `composite-generic-ranking-v11`, `off-search-detail-transport-v5`, Confirm's cocoa pre-fill and `label-estimate-compatibility-v1` (including reopen) are unchanged.
5. **Bundled rows frozen.** No CoFID, USDA, TFDA or Ciqual row's band may change (section 4.2 of the Ciqual admission). The gate scanned every bundled name, description, TFDA source name and alias on 11 November 2026: none has the phrase as its primary name. A test asserts that the display reading equals the v2 band for every bundled record, and v2 is frozen beside the existing v1 reader.
6. **Effect.** Online and personal-library rows with such a name show the normal notes ("95% cocoa", or "95% cocoa · requested 90%") instead of "Cocoa % not stated". Because only the name states it, the detail note says so: "The product name states 95% dark chocolate." (with "; you asked for 90%." when different), never "Source covers 95% cocoa." (local Qodo review, 11 November 2026). Their ranking, grouping into Best or Other matches, and estimate compatibility are unchanged.

### 2. Exact online cocoa match shown first

A presentation change to the Search screen only.

1. **Which rows.** When the request names a cocoa percentage M, an online row (one in today's "Added from online database" set) whose display reading (rule 1.3) is the point band `[M, M]`.
2. **Where.** Those rows move out of "Added from online database" into a new section at the top of the results, after the interpretation note and before "Best matches", headed "Online products with M% cocoa" (M as the user typed it). Their order within the section is the online order. Other online rows stay in "Added from online database".
3. **What does not change.** Row text keeps "Packaged product · … on label", so provenance stays visible. The ranked match list (`route.matches`), its order, the composite ranking version, capture evidence, stored records, exports and Developer tools are unchanged. Confirm is unchanged. Bundled rows never enter the new section.
4. **Point only.** An online row with a range ("85-95% cocoa solids"), an open-ended band or a blend stays where it is today, even when the range contains M.

### Expected screens after the change

| Search | Top section | Godiva row | TOPS row |
| --- | --- | --- | --- |
| dark chocolate 90% | "Online products with 90% cocoa": Godiva | `90% cocoa` | `95% cocoa · requested 90%`, in "Added from online database" when found |
| dark chocolate 95% | "Online products with 95% cocoa": TOPS | `90% cocoa · requested 95%`, in "Added from online database" when found | `95% cocoa` |

Bundled sections keep their current order and notes.

## Architecture

- Rule 1 is a change to `CocoaPercentPolicy` (application, pure): a new `displayBand(_:)` and the phrase reader; `band(...)` and `prefillBand(text:)` are untouched. `note` and `caution` switch to `displayBand`.
- Rule 2 is a change to `GenericFoodSearchViewModel` (presentation): a new `exactOnlineCocoaMatches` list, with `onlineMatches` excluding it, and one section in `GenericFoodSearchView`. It reads `CocoaPercentPolicy.displayBand` and `requested(query)`; no new port, no infrastructure change.
- No new dependency direction. No schema, archive or export change. No egress change.
- Versions: `CocoaPercentPolicy.version` becomes `cocoa-percent-policy-v3`. It is stored nowhere (no evidence, capture, archive or export reads it), so nothing needs to decode differently. The grouping has no version stamp, as #308 and #391 have none.

## Tests (expectations fixed before code)

- **v3 phrase:** "95% Dark Chocolate", "95 % dark chocolate", "Dark chocolate 95%", "95% dark chocolate bar" and "95% Dark Chocolate, organic" read `[95, 95]`.
- **v3 refusals:** "Digestive biscuits with 70% dark chocolate", "Almonds in 70% dark chocolate", "70% dark chocolate chips", "Brand 70% dark chocolate", "110% dark chocolate", a matching phrase only in the description, and a name with two different readings all give the v2 result.
- **v2 untouched:** `band(...)` still returns nil for "95% Dark Chocolate".
- **Pre-fill:** every pinned rule 2 pre-fill phrase gives the same result as under v2; label text and the product name "95% Dark Chocolate" give no pre-fill (`prefillBand(text:)` and `LabelEstimateCompatibility.prefill(name:)`).
- **Freezing:** `band(...)` is not modified and stays checked against the frozen `V1BandReader`; the display reading equals `band` for every bundled CoFID, USDA and TFDA input and for all 29 pinned Ciqual records.
- **Ranking untouched:** a personal-library "95% Dark Chocolate" row changes no bundled row's tier key or order for a 96% request; `OFFHTTPSearchTransport` is not modified and keeps reading `band`, so its explicit-hit order is unchanged by construction (its existing ordering tests still run).
- **Compatibility:** an online row with a display-only point band is refused by `isCompatible`.
- **Grouping (view model):** for "dark chocolate 90%" with Godiva, TOPS and bundled rows, the new section holds only Godiva, "Added from online database" holds TOPS, and the close and other bundled lists are unchanged. With no exact online row, there is no new section. With no cocoa percentage in the request, there is no new section. Range, open-ended and blend online rows never enter it. The new section plus `onlineMatches` equals today's online list, in order, with no overlap.
- **Render:** the section heading, and the provenance line on its rows.
- **Evaluations:** FoodSearchQuality and FoodQueryEvaluation replays unchanged; the ranked list is not touched.

## Decisions for the owner

1. **Placement and heading** of the exact online section. **Decided by the owner, 11 November 2026:** at the top, headed "Online products with M% cocoa".
2. **Point bands only** for that section, not ranges that contain M. **Decided by the owner, 11 November 2026:** exact (point) bands only.
3. **Phrase forms** for v3: the whole primary name is `N% dark chocolate` or `dark chocolate N%`. **Decided by the owner, 11 November 2026:** these two forms only, widened later from real misses.

The owner also asked, on 11 November 2026, for a labelled estimate of nutrients an Open Food Facts product does not list (for example Godiva's fibre). That is a separate contract, drafted on its own; it does not change the rules above.

## Gate record

Architecture gate, 11 November 2026: PASS WITH CHANGES, no blocker. Findings and how they are applied:

1. The v2 band feeds the composite tier keys (`CompositeGenericFoodSearch.swift:77`), so a personal-library row with the phrase could take tier 2 from a bundled row. Applied: the phrase is read only by `displayBand`, never by tier keys (rule 1.3 and 1.4); ranking v11 unchanged.
2. `OFFHTTPSearchTransport.swift:150` orders explicit hits by band. Applied: it keeps `band` and is not modified, so v5 discovery order is unchanged.
3. Freezing test. Applied: `band` itself is unchanged (still checked against the frozen v1 reader), and a new test asserts the display reading equals `band` for every bundled record.
4. Name-based pre-fill. Applied: rule 1.4 and a test for `prefill(name:)`.
5. Rule 1.6 overstated admission for online rows. Applied: rule 1.6 rewritten.

