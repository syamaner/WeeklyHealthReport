# UX revamp v1: journeys, contract changes and architecture gate

Status: **agreed design, 11 October 2026. Specification for #193; implementation not started.**

Wireframes: [`docs/designs/ux-revamp-v1/`](designs/ux-revamp-v1/README.md) and the interactive canvas linked there. Programme: #140. Phase issues: #194 to #200.

The app already has enough capability to make the core journeys useful, but its screens expose the verification machinery: finding a source, reviewing a proposal, accepting a match, entering an amount and saving feel like separate tasks. This revamp keeps the source and safety rules and changes when and how they appear. Broader feature expansion is paused until the revamp journeys are delivered and checked on a device.

## Principles

1. **One journey per intent.** "Log something I ate" is one flow that ends on one Confirm screen, whichever route started it.
2. **Show a rule where it blocks.** An unresolved amount or a material difference belongs beside the Log button; a source identifier belongs behind details.
3. **Plain language first.** Results say "UK reference · cooked · 248 kcal for 150 g", not provider stages, scores or record IDs. Technical detail lives in Developer tools.
4. **Honest states.** Empty is not zero, unknown is not zero, estimates are labelled and partial totals are known minimums.
5. **Repeat logging is fast.** The slow, evidence-heavy work happens once, when a favourite is created.

## Navigation

Hub and spoke from Home, no tab bar. Settings sits behind a gear button on Home.

```
Home ─┬─ Food Log ─┬─ Saved entry ── Edit (Confirm)
      │            └─ Add food
      ├─ Add food ─┬─ Search results ─┬─ Confirm
      │            │                  └─ Web lookup ── Confirm
      │            ├─ Barcode ── Search results / Confirm
      │            ├─ Paste or dictate ── Confirm (per item)
      │            └─ Favourites
      ├─ Quick add sheet (water, favourites)
      ├─ Health ── Export
      ├─ Today's notes
      └─ Settings
```

All destinations are values of one route type handled by one navigation coordinator. Sheets (quick add, alerts) are presentation state of the screen that owns them. Destinations that need an identifier (a saved entry, a search result, a web lookup) are also presentation state of the screen that owns them; they are not route values and restore to that screen.

## Screens

| Screen | Purpose | Key states | Phase |
|---|---|---|---|
| Home | Today's food (energy, protein, carbohydrates, fat, water, entry count), Add food, quick-add chips, health today so far, notes | Empty log, partial coverage, health unavailable, loading | #199 |
| Add food | One search field taking food and amount in the user's words; barcode, paste or dictate, favourites; favourites and recent foods | No recents, no favourites | #196 |
| Search results | Detected amount and preparation as editable chips; plain result rows; one progress line with Stop; online additions as their own group; "Not what you ate?" with web lookup and barcode | Searching, stopped, no result, conflicting query, offline | #196 |
| Web lookup | One suggested source with match type, quoted text behind a disclosure, "Use this source", other sources | No key, no usable source, conflicting source, unavailable | #196 |
| Confirm | Food, inline blocking decision, amount (unit, plate, When), nutrition for the amount, source details, optional "Save as favourite", one Log action | Blocked (with reason), ready, saving, failed, saved | #195 |
| Quick add sheet | Preset amounts or custom, time, Log | Custom amount invalid | #198 |
| Food Log | Day navigation, totals strip, entries by time with unknown flags, swipe to remove, Removed with Restore | Empty day, partial, failed, past day | #197 |
| Saved entry | Read-only amount, time, nutrition, source, history; Edit; Remove with confirmation | Loading, missing, unsupported conversion, failed | #197 |
| Favourites | Quick-add order (first four on Home), other favourites, create from search, barcode or web lookup; photos "Not yet available" | Empty | #198 |
| Health | Period picker with visible range, summary tiles, grouped sections, Copy all; Full Page via the iOS screenshot buttons | No data per metric, no access, loading, failed | #200 |
| Export | Day (today up to the refresh cutoff, or one of the previous seven days), "Included" preview (health data, nutrition from the selected Health source, notes, exact file), one Export action, verified result; Drive setup lives in Settings. Food-log entries are not exported today; adding them is #97 | Not set up, preparing, exporting, verified, failed | #200 |
| Settings | Food search (online database, web lookup key, market), export (Drive account, folder), data (backup, receipts, nutrition updates), Apple Health (medication access), about (privacy, developer tools) | Key missing, Drive disconnected | #194 |

Copy follows the existing house style: British spelling, sentence-case buttons, no emoji, no interpretation, and absence named as a state ("No glucose data is visible, or Health access was not granted.").

## Contract changes

Each change is versioned; existing stored records, archives and exports decode and re-encode unchanged. Each lands in the phase that needs it, with contract tests written first.

### 1. Today-so-far health projection (#199)

Home may show provisional health values for the current local day: cumulative metrics so far (steps, active energy) and latest measurements with their time (weight, blood pressure), plus last night's sleep. Values are labelled "so far" or carry their timestamp.

- A new pure projection with injected calendar and clock, separate from completed-day report and export code. HealthKit statistics are still used for cumulative values; sources are never summed manually.
- Three distinct day semantics stay distinct: Health report period averages use completed days; the Daily JSON export keeps its selected-day rule under [daily-export-contract.md](daily-export-contract.md) (today from local midnight to the frozen refresh cutoff, or one of the previous seven complete days); Home's today-so-far values are a separate provisional projection. Tests prove the report and export outputs are unchanged.
- Unavailable reads are "no visible data or no access", never zero.

### 2. Confirmation v3 (#195)

Amends `food-confirmation-contract-v2.md` and the policy versions it references.

- **One action.** Pressing Log is the explicit acceptance of the displayed food, amount and source. The separate "Accept this match" step is removed. The saved assertion records the same facts as today's acceptance.
- **Typed requirements.** Save requirements become typed values produced by pure application policy. Presentation renders them generically; copy no longer tells the user which disclosure to open.
- **Inline decisions.** A material difference (preparation, bone, skin, drained state, packing medium, fortification, serving basis, edible quantity) appears as an inline choice. Choosing an option that does not match the source records a labelled estimate, replacing today's free-text "explain the closest match". The set of material differences stays closed.
- **When.** The user may set an earlier time or past local day. `FoodReportingDay` derives the reporting date from the chosen time. This adds an explicit occurred-at value; it does not rewrite existing records. Changing a logged entry's time is an ordinary new version.
- Identity correction leaves the primary Confirm flow and is reached from the saved entry or a secondary sheet.

Contract tests: a material difference cannot be logged without an explicit choice; a non-matching choice is persisted as an estimate; unknown and bounded values survive; backdated entries land on the chosen day across DST; historical v1/v2 payloads decode and re-encode byte for byte.

### 3. Single-step web review (#196)

Amends the review manifest in `generic-food-proposal-integration-v1.md`.

- The three acknowledgements (identity, basis, nutrients and unknowns) are replaced by one review action: the user chooses the match type (exact product or similar food estimate) on a screen that shows the source, basis, values and unknowns together, then chooses "Use this source".
- A new manifest version records that single acknowledgement and the screen content it covered. Source binding, hashes, the chosen scope and every existing save blocker for exact products are unchanged.
- Only a bound, non-conflicting proposal can be used, as today.
- The applicability gate is retained unchanged: confirmation still requires a successful applicability check, only the current suggested eligible candidate can prepare confirmation, and `none`, `clarify`, rejected IDs, non-preferred alternatives and unavailable checking remain blocking. The single review step changes presentation and the manifest acknowledgement only. Regression tests cover each blocking outcome through the new screen.

### 4. Quick add (#198)

- A favourite stores its source-bound product, resolution and default amount. Quick add logs a new version through the same confirmation policy with a one-step sheet; nothing logs on a single tap.
- Plain water uses one fixed reference record that contributes water (mL) and no energy. Water totals aggregate daily-first.
- Editing a favourite never rewrites past entries.
- Confirmation v2 reuse rules are retained. A favourite with known identity uses the one-step sheet. An unknown-identity estimate is not eligible for exact personal-library reuse, so a favourite made from one keeps the estimate label and its provenance and always opens the full Confirm screen for fresh explicit confirmation. Re-resolution keeps its strict identity requirements. Relaxing either rule needs its own versioned contract.
- Contract tests: quick add produces the same versioned, source-bound log entry as Confirm; an unknown-identity favourite cannot use the one-step sheet; water aggregates daily-first in mL.

## Architecture gate

### Responsibilities

| Layer | Owns | Must not |
|---|---|---|
| Domain (`FoodLedgerDomain`, app `Models`) | Identity, nutrition, quantity, aggregation, requirement and difference types | Import SwiftUI, HealthKit, GRDB, networking or concrete clocks |
| Application (`FoodLedgerApplication`) | Confirmation policy, save requirements, entry-route inputs, projections, quick-add and favourite services | Format text or hold view state |
| Infrastructure (GRDB, HealthKit client, providers, Keychain, Drive) | Adapters behind consumer-owned ports | Leak framework types across ports |
| Presentation (`FoodLedgerPresentation`, app `Views`) | Screens, view models, copy, navigation state | Aggregate, decide eligibility or call adapters directly |
| Composition root | Wiring concrete adapters, registering routes, cards and settings sections | Contain business rules |

### Extension points (real variation only)

- **Entry routes.** Search, barcode, list, favourite, water and, later, label photo each produce the same confirmation input. A new route is an adapter registered at the composition root; Confirm does not change.
- **Confirmation requirements.** A closed, typed set rendered generically. New requirement kinds need a contract version, not a plug-in.
- **Home cards and Health tiles.** Each feature contributes a card or tile from its own projection. Adding a highlight does not modify Home.
- **Settings sections.** Each feature contributes its section; Settings arranges them.
- **Navigation.** One route type and coordinator replace the report-hosted stack in `WeeklyReportView.swift`.

Fixed behaviour stays concrete: no universal metric framework, no generic repository, no protocol-per-method interfaces.

### Enforcement

- Package target dependencies keep domain and application free of UI and infrastructure; the existing boundary check in CI extends to new targets.
- Alternate implementations of a port (in-memory and GRDB stores, provider fakes) pass the same contract tests.
- View-model tests cover orchestration changes; simulator UI tests cover each route.

## Delivery

| Phase | Issue | Contract change | Device check |
|---|---|---|---|
| 1 | #194 Navigation shell and Settings | None | Every route reachable |
| 2 | #195 Confirm | Confirmation v3 | Full log journey |
| 3 | #196 Add food, search, web lookup | Web review | Reported queries |
| 4 | #197 Food Log and saved entry | None | Edit, remove, restore, no blank sheet |
| 5 | #198 Favourites, quick add, water | Quick add | Water and favourite from Home |
| 6 | #199 Home | Today-so-far projection | Values against Apple Health |
| 7 | #200 Health and Export | None | Copy all, Full Page, export |

Each phase is one PR with package tests, the simulator suite, Xcode static analysis, boundary checks and a recorded device check. Simulator evidence proves software behaviour; device usability and Apple Health comparisons remain separate manual validation.

## Out of scope

Label and food photo capture (#93), focused nutrient summaries (#145), trends (#147), HealthKit writes, new providers and medical interpretation.
