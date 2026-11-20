# Personal food database: food details from the catalogue (I1)

Status: **approved by the owner on 20 November 2026, with the recommendations for I1-D1 to I1-D3, and
implemented in #547 (sections I1.1 to I1.5, 4 and 5). The Jev terms of section I1.6 (decision I1-D4)
were approved by the owner the same day, with brands, pack size, pack type, category, product type and
state allowed; no Jev caller is built in #547.** Written at the owner's request on
20 November 2026, after they found themselves adding food details by hand for every item from Your
food database and asked for sensible defaults to be classified automatically. The owner then asked
for classification to run through Jev first, with questions only afterwards, and for the OpenRouter
rules to be relaxed. The implementation phase's architecture gate record is in #547.

It is a delta on [import v1](personal-food-catalogue-import-v1.md) (sections 4.1, 4.2 and 7),
[labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md) ("estimates
v2": amendment A2 and section 5), the [label photo estimates](personal-food-catalogue-off-estimates-v1-proposal.md)
schema `personal-food-catalogue-estimates-v3`, the [own merge amendment G4](personal-food-catalogue-own-merge-amendment-v1.md),
the [Confirm rules review](confirm-rules-review-v1.md) (#470), and Amendment A1 as recorded in
[identity contract](food-identity-nutrition-contract.md) section 8 and
[`unified-food-search-contract-v1.md`](unified-food-search-contract-v1.md). It repeats none of them,
and everything they say that this document does not name stays as written. On acceptance each
amended document gains a dated note pointing here.

## 1. Why

Every Your food database entry reaches Confirm with its food details unknown, so Log is blocked by
"This source does not say: bone, skin, drained state, packing liquid or none, fortification" until the
owner fills them in by hand, on every log of every food. Import v1 section 4.1 sets bone, skin,
drained state, packing medium and fortification to unknown on every entry and says "Nothing is
inferred from the title". Preparation is unknown too wherever `state` is not `raw` or `cooked`
(`PersonalFoodDatabaseCandidateBuilder.preparation`).

Counts only, from the owner's catalogue on 20 November 2026 (836 entries; private data, not checked by
the reviewers): 307 entries merge a generic record, which supplies its own identity but whose bone,
skin, drained and packing facts are usually unknown as well, and 350 have a state that maps to an
unknown preparation (242 `unknown`, 29 `canned`, 22 `frozen`, 50 `dried`, 7 `smoked`). In practice
every entry asks.

The questions exist so that, for example, raw chicken with skin and roast chicken without skin are
never logged with each other's values (Confirm rules review, "What stays closed"). For almost all of
the owner's foods the answers do not change from one log to the next, so they belong in the catalogue,
decided once and reviewed once, as the owner's assistive principle asks: the build pre-fills, the
owner validates, and every value stays visible and changeable.

## 2. What changes

### I1.1 Schema `personal-food-catalogue-estimates-v4`

A new schema that admits everything `personal-food-catalogue-estimates-v3` admits, with two
differences: every entry gains one required key, `identity_facts`, and the `product_dataset_photo`
source type is admitted but not required (the v3 rule `photo-missing` does not apply to v4). Every
other v3 rule, including the photo rules for a photo estimate that is present, applies unchanged. The
skill writes v4 only when at least one entry has a non-null `identity_facts`; otherwise it writes v2 or
v3 exactly as today. Code that tests for the v3 schema by name (`carriesEstimates`, the photo source
type list, the codec's schema switch, the skill's writer and estimate applier) is extended to v4.

Strict decoding is unchanged: `identity_facts` must be present, and its value is `null` (no facts,
exactly today's behaviour) or an object with exactly these keys, each with a closed value:

| Key | Values | Maps to |
|---|---|---|
| `preparation` | `as_sold`, `raw`, `cooked`, `unknown` | `PreparationState` kind; `cooked` with no method |
| `bone` | `with_bone`, `boneless`, `not_applicable`, `unknown` | `BoneState` |
| `skin` | `skin_on`, `skinless`, `not_applicable`, `unknown` | `SkinState` |
| `drained` | `drained`, `undrained`, `not_applicable`, `unknown` | `DrainedState` |
| `packing_medium` | `as sold`, `not applicable`, `water`, `brine`, `oil`, `olive_oil`, `sauce`, `unknown` | `PackingMediumState.named` with that exact text, or `.unknown` |
| `fortification` | `unfortified`, `unknown` | `FortificationState` |

- `as sold` and `not applicable` are the frozen packing names of Confirm rules review rule 2.3, so a
  value from the catalogue and one the owner picks in the Food details sheet are the same stored value.
  The other names are the identity contract's own examples and the values the bundled CoFID records
  use. `PackingMediumState.named` is free text, so no record, archive or export changes.
- **Fortified is not admitted.** The record model ties fortified to item class `fortified_food` and
  declared fortificants, and a fortified fill withdraws estimates (Confirm rules review rule 1.3). A
  fortified food keeps `unknown` and is asked on Confirm, as today (decision I1-D2).
- **Preparation must agree with `state`.** When `state` is `raw`, `preparation` is `raw` or `unknown`;
  when `cooked`, `cooked` or `unknown`. For `canned`, `frozen`, `dried`, `smoked` and `unknown` states,
  `preparation` is `as_sold` (the values describe the food as sold) or `unknown`; never `raw` or
  `cooked`, because the merge rule (import v1 section 4.1) relies on `state` alone. An `unknown`
  preparation leaves today's mapping from `state` in place.
- A v4 file carries `estimate_evidence` and every item's `estimated_nutrients`, either of which may be
  empty, as estimates v2 allows; a catalogue with facts but no estimates is written as v4 with both
  empty.
- A v3 file stays valid and imports exactly as today. The importer accepts v4 alongside v3; no stored
  release is rewritten.

### I1.2 Rejection rules (import v1 section 4.2, added)

The importer rejects the whole file, with a visible reason and the active release unchanged, for an
`identity_facts` object with a missing or unknown key (`facts-keys`; a repeated key fails earlier as
`duplicate-key`, as for every object), a value outside its
closed list (`facts-value`), and a `preparation` that disagrees with `state` under I1.1
(`facts-state`). These three codes form a new `estimatesV4Only` set beside `estimatesV3Only`. An
`identity_facts` key in a v1, v2 or v3 file stays an unknown item key (`item-keys`), so no earlier
schema's codes change. Fixtures live in `docs/fixtures/personal-food-database-estimates-v4/`, whose
manifest the skill's checker and the Swift importer tests both read, with the existing manifest
equality test extended to it.

### I1.3 The candidate's identity (import v1 section 4.1 and Amendment A1, amended)

- **No merge.** The candidate's `DecisiveIdentity` takes each fact from `identity_facts` where it is
  not `unknown`, and from today's mapping otherwise (preparation from `state`, every other fact
  unknown).
- **Merge (amends identity contract section 8, Amendment A1, for v4 files only).** Today's conditions
  stay (`mergeEligible`: entry state `raw` or `cooked`, per 100 g, record preparation known and equal,
  record not fortified, record per 100 g edible). One condition is added: no fact stated in
  `identity_facts` is known on both sides and different from the record's, judged with
  `EstimateIdentityComparison.contradictions` (the A2 comparison: unknown on either side never
  contradicts; `as_sold` and `raw` are compatible). When eligible, the entry takes the record's
  identity as A1 says, and each fact the record leaves unknown is taken from `identity_facts`; this
  replaces A1's "takes the record's identity for every other facet" for v4 files only. When
  ineligible, the record is offered as its own "Generic" row, as `PersonalFoodDatabaseFoodSearch` already
  does, and the file is not rejected (the codec's `merge-condition` checks file fields only).
- **Estimates use the same identity (v4 files only).** For a v4 file the importer's
  `estimate-contradiction` keeps every condition of `PersonalFoodDatabaseEstimateAdmission.contradicts`
  (state-derived preparation, a fortified record, the per 100 g edible basis) and adds one:
  `EstimateIdentityComparison.contradictions(record:confirmed:)` between the estimate's record and the
  entry's identity built under this section is not empty. G4's `estimate-own-merge` uses the
  facts-aware `mergeEligible`. So the importer and Confirm's estimate withholding
  (`ApprovedEstimateEligibility`) agree, and a fact can never leave an admitted estimate that Confirm
  withholds on every log. v1 to v3 files keep today's check exactly, and so does a v4 entry whose
  `identity_facts` is null (added at implementation review, 20 November 2026), so an all-null v4 file
  imports exactly as its v3 twin.
- **An entry that would disappear.** If a fact makes the merge ineligible and the entry then has no
  known nutrient of its own (no label or estimate value), the builder offers no entry row
  (`PersonalFoodDatabaseCandidateBuilder.build` returns nil) and only its "Generic" row remains. The
  checker lists such entries separately as "entry would disappear", and the skill does not write that
  fact unless the owner accepts it.
- **Method version.** Candidates built from a v4 file carry `CandidateMatchMetadata.methodVersion`
  `pfc-resolution-v2`; v1 to v3 files keep `pfc-resolution-v1`, which A1 names. The release's
  `pipelineVersion` follows the same rule, and `dedupeDatabaseRows` and the A1 rows in both contracts
  name both versions. The version is a function of the file's schema, not one constant (today
  `PersonalFoodDatabaseCandidateBuilder.methodVersion` serves every use):
  `PersonalFoodDatabaseReresolutionProvider.target` and the route's and re-resolution's evidence
  `captureMethodVersion` take it from the snapshot's schema, so a re-resolution target and its
  candidate always carry the same version. Resolver-built "Generic" rows (CoFID, USDA and TFDA
  resolvers) keep `pfc-resolution-v1` for every schema.
- **Nothing inferred in the app.** Import v1 section 4.1's "Nothing is inferred from the title" becomes,
  for v4 files: "The app infers nothing from the title; a fact the file states was proposed by the
  skill and approved by the owner (I1.5)."

### I1.4 Confirm, search, saving and records (import v1 section 7 and estimates v2 section 5, amended)

- **Stated by the source.** A fact the catalogue states counts as stated by the source, like a fact on
  an Open Food Facts record. When the selected database candidate states every fact,
  `sourceIdentityMissing` is not raised and Log needs only an amount. Any fact still `unknown` is
  asked exactly as today. `FoodLogPolicy`, `IdentityCompatibility` and `food_confirmation_v5` are
  unchanged.
- **Expected identity.** Tapping a search row opens Confirm through `GenericFoodConfirmationRoute.choosing`,
  which puts the chosen row first and makes its identity the expected identity. So a database row the
  owner taps raises no difference, whatever the composite ranking (`composite-generic-ranking-v11`)
  placed above it. If the owner then switches on Confirm to another row ("Choose a different match"),
  each fact that differs is today's difference question (for a non-generic row, unknown on either
  side is a difference; for a generic row only a different known value is, under
  `FoodConfirmationState.materialDifferences`), as for any two candidates today: for example,
  switching from a database row with stated facts to its "Generic" row asks about each fact the
  record states differently. Both directions are listed and covered by contract tests.
- **One visible line.** Confirm shows "Food details from your food database:" followed by the facts
  taken from `identity_facts`, in plain words (for example "raw, boneless, no packing liquid, not
  fortified"); facts that came from a merged record are not listed as the catalogue's. The builder
  writes this as one note in the candidate's existing `CandidateMatchMetadata.materialDifferences`,
  starting with the frozen prefix "Food details from your food database:", so no new field is needed;
  the note is saved with the candidate, so its text is frozen data, not copy. The line is hidden when a
  correction or a reopened entry applies. It is never behind details, because it is what lets Log
  through.
- **Changing a fact.** The owner can still change any fact: through "Add food details" while a fact is
  unknown, and through "Correct food details" when the catalogue states every fact. Under I1-D1 no
  typed reason is needed when every changed fact is one the note lists (taken from `identity_facts`)
  or one the candidate left unknown; changing a fact the merged record states, or the preparation that
  comes from `state`, still needs a typed reason (Confirm rules review rule 2.2).
- **Search (composite `composite-generic-ranking-v12`).** The progressive search fails its whole local
  stage when any row hard-contradicts the request (`ProgressiveFoodSearchCoordinator`, using
  `ConservativeFoodSearchCoverageAssessment.hasHardContradiction`), and the database route, unlike the
  bundled adapters (`FoodPreparationDiscoveryPolicy.accepts`), does not leave such rows out. Stated
  facts would make this happen more often (a "Rice, dried" entry stated `as_sold` for "cooked rice").
  So the database route leaves out every row it would offer, entry row or "Generic" row, for which
  `ConservativeFoodSearchCoverageAssessment.hasHardContradiction(row.candidate.candidate, request:)` is
  true, using the request the route receives, as the bundled adapters leave out contradicting records.
  A record's "Generic" row is still offered when it does not itself contradict. The filter runs in
  `PersonalFoodDatabaseFoodSearch.route`, per row, before the row counts towards `maximumEntries` and
  before its releases or capture manifest are added; an entry with no row left counts nothing. If no
  row is left the route returns its no-result, which the composite ignores, so the composite's
  fallback, guidance and suggestions are those of v11 without the database route.
  `dedupeDatabaseRows` sees only rows that passed, and `PersonalFoodDatabaseReresolutionProvider` does
  not filter. This is a database route change under a new composite version, `composite-generic-ranking-v12`; with every
  `identity_facts` null the only change from v11 is that rule. Stated facts otherwise take part in
  coverage and the preparation partition unchanged; an `as_sold` row is no longer "unverified". The
  same failure already exists today for entries stated `raw` or `cooked` through `state`, so v12 also
  fixes that. Search is stricter than the A2 comparison: a request for raw or cooked leaves out an
  `as_sold` row (as the bundled adapters do), so stating `as_sold` hides the entry from "raw ..."
  searches (I1.5 step 5).
- **Saving.** Unchanged in shape: the saved product version carries the candidate's identity, as for
  every source, and cites the database release. No new record type, field, operation type or export
  schema change (food daily export v2 carries no identity facts); older builds decode the saved
  records unchanged. A log saved without a correction is eligible for quick add straight away (quick
  add rule 3 as rewritten by Confirm rules review rule 3.5), and re-log and quick add rebuild from the saved candidate, so a later catalogue
  import that changes a fact does not change an earlier log.
- Estimates, the quality tier, the fortification estimate allowance and every other Confirm rule are
  unchanged.

### I1.5 How the skill writes the facts (skill procedure, amended)

1. **Jev first, then the agent's rules.** Each entry is first classified by Jev (`jev-1.13` through
   OpenRouter) under the terms of section I1.6: one typed choice question per fact, with the closed
   values of I1.1 as the choices. The agent then checks every answer against step 4's rules and the
   entry's own label evidence in the private workspace. A fact is a **recommended row** when Jev's
   answer and the agent's check agree; otherwise it is flagged with both views. No web or Open Food
   Facts query is made for it.
2. **Reasons recorded privately.** Each proposed fact keeps, in the private workspace only, a short
   reason (for example "steak cut, sold off the bone", "fresh produce, no packing liquid", "dry tea
   leaves, as sold") and its basis: the title, the category or the label. Nothing of this enters the
   file beyond the fact itself.
3. **Owner review only after classification.** The owner is asked nothing until Jev and the agent
   have classified every entry. Proposals then go to the owner as review sheets, the same way estimates
   do, with recommended rows first and flagged rows marked. Only facts the owner approves are written; anything not approved stays `unknown` (or the whole
   object `null`). The owner may approve a sheet in bulk, as they did for the recommended rows of the
   estimate sheets on 18 November 2026 (decision I1-D3).
4. **When to leave a fact unknown.** The agent proposes `unknown` when the title does not settle it (a
   "chicken" with no cut named, a canned fish with no packing liquid named), and never proposes a fact
   from the category alone where the category has both kinds (meat and fish can have bone and skin;
   vegetables can be canned in brine).
5. **Merge and estimate check.** Before export the checker lists every entry whose facts would make
   its merge ineligible, or would make an estimate contradict, under I1.3, so the owner can correct the
   fact or accept a separate generic row. The checker and the Swift `mergeEligible` share one synthetic
   fixture set (eligible, ineligible by a fact, eligible with a fill) and must agree. It also lists
   entries proposed `as_sold` whose titles or aliases are usually searched with "raw" (nuts, seeds,
   dried fruit), so the owner can keep `unknown` for them.

### I1.6 Relaxed terms for Jev through OpenRouter (developer tooling, `privacy-and-egress.md` amended)

Today Jev may see only generic composition-table words, never a product title or brand, and the owner
approves each list of pairs before it is sent (`privacy-and-egress.md`, estimate quality tiers). For
identity classification that is too strict, because the title is what says "thin cut sirloin" or "in
brine". These terms replace the per-list approval for this purpose and for the existing estimate
quality tiers; every other OpenRouter route (the app's web lookup and label photo reading) is
unchanged.

1. **Destination.** `https://openrouter.ai/api/v1/systemone`, model `jev-1.13` only, through the
   skill's HTTP client (pacing, retry, backoff and Retry-After). A zero-data-retention endpoint with
   data collection denied is pinned where one exists for the model; where none does, the run's
   summary says so.
2. **What each request may carry.** One food description built by the skill from the entry: its title,
   with pack sizes and quantities kept; its brand; its pack size and pack type (for example bag, can,
   jar, tin or bottle) where the entry or its title states one; its category, product type and state;
   and the fixed typed questions with their closed choices. Shop names that the private config lists
   only as receipt or shop markers, not as the entry's brand, are removed. For estimate tiers, the two
   generic descriptions sent today, and the same fields where they help.
3. **What it never carries.** Shop names other than the entry's brand, receipt text, notes, prices, amounts, dates, nutrient
   values, entry identifiers, file names, photos or any personal data. Every description passes the
   skill's deny patterns (`http_client.safe_query`'s personal-data checks) before sending; one that
   fails is not sent and its facts are left for the agent and the owner.
4. **Standing approval with an audit trail.** No per-list approval: the exact request list is written
   to the private workspace before the run, the run stops after 2,000 requests, and its summary
   (count sent, count refused by the gate, retention status) is reported to the owner. The owner can
   withdraw this approval at any time, which returns both uses to per-list approval.
5. **Answers advise only.** Jev's answers feed the review sheets (I1.5) and estimate tiers; they
   authorise nothing, and nothing from them enters the repository.
6. **Key.** The OpenRouter key already approved for these uses, read at run time into the process
   only, never printed or stored.

Approved by the owner on 20 November 2026. `privacy-and-egress.md`'s estimate quality tier paragraph is
replaced by these terms.

## 3. What stays closed

- Nothing is logged or saved without the owner's explicit Log; the amount is always the owner's.
- Unknown is never zero, and an unknown fact is still asked.
- No medical classification, target or advice; these facts describe the food, not the owner.
- No app egress: the app reads only the imported file. The skill's classification sends to one
  destination already used for the private catalogue (OpenRouter's System One endpoint, model
  `jev-1.13`), only under the terms of section I1.6.
- Sealed evaluation sets are not opened.

## 4. Compatibility and rollback

- v1, v2 and v3 files keep every rule, rule code and fixture. A v4 file whose every `identity_facts`
  is `null` gives the same candidates as its v3 twin except for the database release (ID,
  `schemaVersion`, `pipelineVersion`) and `CandidateMatchMetadata.methodVersion` `pfc-resolution-v2`:
  identity, nutrients, provenance apart from the release ID, row order and `materialDifferences` are
  equal.
- **Nutrition updates.** Re-resolving a saved log against a v4 release yields no proposal for a fresh
  candidate whose stated fact differs from the saved log's (`FoodReresolutionService.proposals` drops
  it; constructing one directly throws `incompatibleIdentity`), and the log keeps its values. Where
  they agree, the update proceeds. Today only merged entries and the raw or cooked preparation are
  stated, so the catalogue's facts widen this; covered by a contract test.
- **Rollback.** Re-import a v3 build of the same catalogue; the facts disappear and Confirm asks again.
  Logs already saved keep the facts they were saved with, as any saved product version does.
- An older app build rejects a v4 file at import with its unknown-schema reason, before anything
  changes. An older build that already has a v4 release stored treats it as unreadable and shows the
  database as unavailable; re-importing a v3 build restores it.

## 5. Architecture gate (for the implementation phase)

- **Responsibilities.** Domain: the closed fact values, the v4 schema case, the new rule codes, the
  codec and the mapping to `DecisiveIdentity` (`PersonalFoodDatabaseModel`, `PersonalFoodDatabaseCodec`,
  all in `FoodLedgerDomain`). Application: candidate identity, the facts-aware `mergeEligible`, the
  `estimate-contradiction` addition, the Confirm note and the v12 route filter
  (`PersonalFoodDatabaseCandidates`, `PersonalFoodDatabaseEstimateAdmission`,
  `PersonalFoodDatabaseFoodSearch`, `CompositeGenericFoodSearch`), and, if I1-D1 is accepted, one
  predicate in `FoodDetailsFillPolicy`. Presentation: the Confirm line, shown when the selected
  candidate's `CandidateMatchMetadata.materialDifferences` holds a note with the frozen prefix and no
  correction or reopened entry applies (Confirm does not show these notes for database rows today).
  Infrastructure: none; `FilePersonalFoodDatabaseStore` accepts the new schema case through
  `PersonalFoodDatabaseSchema(rawValue:)` unchanged. Skill: the writer, checker and review sheets.
- **Dependency direction.** Unchanged; no new port or target, and `check-boundaries.sh` needs no
  change.
- **Invariants.** A v3 file imports as before; fortified never comes from the file; preparation never
  contradicts `state`; a fact is used only where the file states it; the importer and Confirm judge
  merges and estimates with the same identity.
- **Extension axis.** A later fact (for example fortified with declared fortificants) is a new schema
  version, never a loosened closed list.
- **Contract tests (synthetic fixtures only; shared with the Python checker where marked).**
  1. Codec (shared): one failing fixture per new code; a v3 file with `identity_facts` gives
     `item-keys` only; a v4 file without a photo estimate passes; v3 and v4 round trips; an all-null
     v4 file equals its v3 twin under the field-by-field rule of section 4.
  2. Candidates (merge fixtures shared): no merge with all six facts gives no `sourceIdentityMissing`;
     partial facts ask only for the unknown ones; a merge takes a record-unknown fact from the file; a
     conflicting known fact drops the merge and offers the record as its own row; a merge-only entry
     whose fact makes the merge ineligible gives no entry row, and the checker reports "entry would
     disappear"; v4 candidates carry `pfc-resolution-v2` and v3 candidates `pfc-resolution-v1`, and
     dedupe accepts both.
  3. Estimates: a facts-contradicting estimate in a v4 file is rejected at import
     (`estimate-contradiction`), and the fortified-record and basis conditions still fire; a v3 merged
     entry that imports today still imports with exactly today's codes; where only the facts make the merge
     ineligible, a G4 own-record estimate is `estimate-contradiction`, not admitted (section 7);
     Confirm's withholding agrees with the
     importer.
  4. Confirm: a tapped database row with stated facts raises no difference and Log needs only an
     amount, including when a CoFID or USDA row ranked above it; switching to its "Generic" row, or
     from a CoFID row to a database row, asks the listed difference questions.
  5. Search: no row the composite returns with a database source, entry or "Generic", has
     `hasHardContradiction`; one fixture whose "Generic" row contradicts (absent) and one whose does not
     (present); the progressive local stage with a v4 entry stated `as_sold` for "cooked rice" does not
     fail; the same for a v3 entry whose `state` is `raw` against a "cooked" query; an `as_sold` entry
     is absent for "raw almonds" and present for "almonds"; with more than 10 hits whose first ones
     contradict, 10 non-contradicting entries are offered and no dropped entry's release or manifest is
     in the confirmation; when every database row is dropped, the outcome, fallback and suggestions
     equal v11 without the database route and the local stage escalates as with no match; with no
     contradicting rows the output equals v11 apart from the version string; with an explicit request
     preparation `as_sold`, an `as_sold` database row sorts ahead of an unknown-preparation row.
  6. Re-resolution: `FoodReresolutionService.proposals` returns no proposal for a stated-fact
     mismatch and nothing is written; constructing that proposal directly throws `incompatibleIdentity`;
     matching details update; re-resolving a saved v3 log against a v4 release yields a proposal whose
     target and candidate both carry `pfc-resolution-v2`; v3 targets and resolver-built "Generic" rows
     keep `pfc-resolution-v1`.
  7. View model: the line appears only when the frozen-prefix note is present, lists only facts from
     `identity_facts`, and is hidden after a correction, on a reopened entry and on a carried fill; the
     note survives a save and decodes on the previous build; I1-D1 behaves as decided.
  8. Re-log and quick add: a v4 log saved without a correction is quick-add eligible and re-logs with
     its saved facts after a catalogue import that changed them.

## 6. Decisions for the owner

Asked one at a time in #546, each with a recommendation.

- **I1-D1. Changing a catalogue fact on Confirm.** Recommendation: **no reason needed.** These are the
  owner's own reviewed facts. If accepted, the change is still not a fill (weight and conversion are
  cleared under rule 2.4, and it is not carried on re-log under rule 3.2); only the reason becomes
  optional, stored as the frozen string "Food details changed from your food database" beside the
  existing fixed reasons. `FoodDetailsFillPolicy` gains one predicate; `FoodLogPolicy` and
  `food_confirmation_v5` are unchanged. The alternative keeps today's rule (a typed reason for any
  stated fact). **Approved as recommended**, limited as implemented to facts the note lists and blanks
  the candidate left unknown (section I1.4).
- **I1-D2. Fortified foods.** Recommendation: **keep asking** (section I1.1). Admitting fortified needs
  declared fortificants and an item class change, which is a larger schema step.
- **I1-D3. Review sheets.** Recommendation: **one sheet per category group**, approved in bulk where
  every row is the recommended one, so 836 entries are reviewed in a handful of sheets.
- **I1-D4. Relaxed Jev terms (section I1.6).** **Approved by the owner on 20 November 2026**, widened
  from the recommendation so that titles keep their pack sizes and the brand, pack size, pack type,
  category, product type and state may be sent, under a standing approval with a written request list,
  a 2,000-request cap per run and a run summary, instead of approving each list.

## 7. Review record

- **Architecture gate, first draft (20 November 2026): FAIL.** Taken: the merge change named as an
  amendment to A1 with its added condition and the A2 comparison; v4 no longer inherits `photo-missing`
  and names the code that tests for v3; rule codes and fixtures kept separate from v3; the A2 and G4
  estimate checks use the same identity; search coverage and ranking effects listed; re-resolution's
  `incompatibleIdentity` added; the Confirm line limited to file facts and carried as a note; I1-D1's
  consequences stated; rollback for a stored v4 release; checker parity fixtures. Corrected, not
  taken as written: the gate read Confirm's expected identity as the composite's first row in every
  case, but a tapped row opens Confirm through `GenericFoodConfirmationRoute.choosing`
  (`GenericFoodSearch.swift`), which makes the tapped row's identity the expected one; the difference
  questions arise only when the owner switches row on Confirm, so no ranking change is a prerequisite.
- **Architecture gate, second round (20 November 2026): FAIL.** It verified the correction above.
  Taken in full: the v12 database route filter for hard contradictions (it also fixes the same
  failure for today's raw and cooked entries); the facts-aware `estimate-contradiction` limited to v4
  and keeping today's conditions; the egress wording (classification reaches the model provider as
  already listed); `pfc-resolution-v2`; the entry that would disappear; the Confirm note's real render
  path; the codec's target; the import v1 "nothing inferred" sentence amended; the re-resolution
  wording; empty estimate keys in v4; the generic-row difference rule. Owner-catalogue counts in
  section 1 remain unverified by the reviewers.
- **Architecture gate, third round (20 November 2026): PASS WITH CHANGES.** All taken: the v12 filter
  covers "Generic" rows too, with its place in the route, the cap, provenance and the all-dropped case;
  the all-null v4 equivalence excepts the release and method version; the method version follows the
  schema so re-resolution keeps working; the `as_sold` against "raw" search effect stated and checked;
  a test that could not fail replaced; the classification fields named for a policy note (I1-D4).
- **After the gate rounds (20 November 2026).** At the owner's request, classification runs through
  Jev first (I1.5 step 1, step 3) and section I1.6 relaxes the Jev terms. These changes were not part
  of the three gate rounds; I1.6 is policy and needs the owner's explicit approval (I1-D4), and the
  implementation phase's gate covers the skill changes.
- **Implementation (20 November 2026, #547).** Sections I1.1 to I1.5, 4 and 5 implemented, with the
  shared fixtures in `docs/fixtures/personal-food-database-estimates-v4/` (written by the skill's
  `test_identity_facts.py`) and the skill's `apply_identity_facts.py` writer, which reads a private
  `pfc-approved-identity-facts-v1` file. One consequence found while writing the tests: a fact that
  makes a merge ineligible is by definition one that contradicts the record, so an estimate from that
  same record (G4) is then `estimate-contradiction`, not admitted; the writer withholds such a fact
  and the checker lists the entry. Section I1.6 is not implemented.
