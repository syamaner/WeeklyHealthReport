# Food identity and nutrition provenance contract

Status: contract v1, accepted for issue
[#89](https://github.com/syamaner/WeeklyHealthReport/issues/89), 19 September
2026. This is a documentation contract, not an implemented schema or authority to
change the app, contact a provider, use a device, write HealthKit data or expand
Google Drive access.

The supporting research remains in
`food-identity-nutrition-architecture-research.md`. This document is the smaller
normative authority that later spikes, evaluations and implementation slices must
share. Where that research describes options, this contract records the decision.

## 1. Normative rules

The key words **must**, **must not**, **should** and **may** are normative.

1. Original capture evidence is append-only. A correction adds an assertion or a
   new version; it never edits the captured bytes, text, hash, time or source.
2. A product identity and a nutrition resolution are different records. The same
   identity version may have several resolution versions, and a product
   reformulation creates a new product version even when its barcode is unchanged.
3. Every one of the 39 catalogue nutrients has exactly one value state in a
   resolution: `measured`, `augmented`, `bounded` or `unknown`.
4. `unknown` is not zero. `bounded` is not an exact number. Neither may be coerced
   to an exact scalar for totals, export or any later HealthKit operation.
5. Matching and merge decisions are per nutrient, not whole-record replacement.
   Evidence that wins for protein does not automatically win for calcium.
6. A hard identity contradiction blocks the candidate regardless of its score.
   Preparation, bone, skin, drained state, packing medium, fortification, serving
   basis and edible quantity are material identity data, not descriptive labels.
7. No conflict is resolved by storage order, update time or silent
   last-write-wins. An unresolved conflict is exported explicitly and the affected
   nutrient remains `unknown` in the effective resolution.
8. Dataset and model identifiers always name an immutable release. `latest`, an
   unversioned URL and a mutable provider response are not reproducible source IDs.
9. The local ledger is authoritative and works offline. Canonical JSON is a
   deterministic projection of a ledger snapshot. Drive remains an explicit
   `drive.file` export/backup path, never the live database.
10. HealthKit remains read-only. A later separately approved plan may make eligible
    exact scalars writeable, but HealthKit can never replace the source-rich ledger.
11. This contract adds no medical classification, interpretation, target,
    diagnosis or treatment advice.

## 2. Identity and version model

Application entity and version identifiers are opaque lowercase UUID strings
generated once and never reused. Entity IDs identify a continuing logical object.
Version IDs identify one immutable snapshot. An integer `version` is a
human-readable monotonic ordinal scoped to its entity; it is not identity and must
not be used as a foreign key. `source_id`, `source_release_id` and external
`record_id` are stable namespaced strings because their issuing source, not this
app, owns their identity.

| Record | Stable identity | Immutable version | Required relationship |
| --- | --- | --- | --- |
| Capture evidence | `evidence_id` | none; the record itself is immutable | May support many product versions and assertions |
| Product | `product_id` | `product_version_id` | A version cites its evidence and decisive identity attributes |
| Personal-library entry | `library_entry_id` | `library_entry_version_id` | A version points to one product version and reusable defaults |
| Log item | `log_item_id` | `log_item_version_id` | A version records occurrence, edible quantity, product version and resolution used |
| Nutrition resolution | `resolution_id` | `resolution_version_id` | A version resolves all 39 nutrients for one product version and named basis |
| Derived daily summary | `summary_id` | `summary_version_id` | A version names the exact log and resolution versions aggregated |
| Dataset/model source | `source_id` | `source_release_id` | A release is immutable and content-addressed or manifest-addressed |

`Product` is the v1 contract name for any loggable food identity, including a
branded product, whole food or user-defined dish; it does not imply packaging. A
generic dataset row is not a mutable product entity. It remains an external source
record identified by `(source_release_id, record_id)` until a confirmed mapping
creates or supports a product version.

The minimum logical record shapes are frozen as follows. Storage layout and indexes
remain #90 decisions, but implementations must preserve these fields and links:

| Record | Required v1 content |
| --- | --- |
| `capture_evidence` | `evidence_id`, kind, capture time, locale, capture-method version, original payload or descriptor, byte hash where applicable, local attachment reference where retained |
| `product` | `product_id`, creation time |
| `product_version` | version ID, product ID, ordinal, optional superseded version, name/brand/variant/barcode, `item_class`, pack facts, decisive identity attributes, evidence/assertion IDs, creation time |
| `library_entry` | `library_entry_id`, creation time |
| `library_entry_version` | version ID, library-entry ID, ordinal, optional superseded version, product-version ID, aliases, optional reusable quantity/measure defaults, creation time |
| `log_item` | `log_item_id`, creation time |
| `log_item_version` | version ID, log-item ID, ordinal, optional superseded version, occurrence time/reporting date, product-version ID or ordered component log-version IDs, confirmed edible quantity, original and effective resolution-version IDs, correction reason, creation time |
| `resolution` | `resolution_id`, product-version ID, named resolution basis |
| `resolution_version` | version ID, resolution ID, ordinal, optional superseded version, algorithm/method version, source-release IDs, exactly 39 ordered nutrient entries, decision/assertion IDs, creation time |
| `daily_summary_version` | summary/version IDs, reporting date/time zone/cutoff, exact input log- and resolution-version IDs, 39 state-preserving totals, optional superseded version, creation time |

Optional branded fields are absent for a whole food rather than filled with invented
values. Required decisive attributes use explicit `unknown`; omission is not a
third meaning. Times are ISO 8601 instants with offsets, reporting dates are ISO
calendar dates, quantities are finite JSON numbers, and arrays with semantic order
retain it deterministically.

The following relationships are frozen:

```text
capture evidence --supports--> product version
                              --> user assertion

product --has immutable versions--> product version
personal-library entry version ----> product version + reusable defaults
log-item version -------------------> product version + edible quantity
resolution version ----------------> product version + named basis + evidence + source releases
log-item version -------------------> resolution version used + edible quantity
summary version --------------------> exact log-item and resolution versions
```

`product_id` groups versions judged to be the same market identity. It does not
mean the formulation is unchanged. A new recipe, nutrient panel, fortification,
pack basis or other decisive attribute creates a new `product_version_id`.
Boneless and bone-in sardines are normally different products, not versions of one
formulation. A barcode may index candidates but is never the product ID.

A personal-library entry is a reusable shortcut, not evidence. Its version may
store a preferred product version, household measure and quantity, but a log still
records what was confirmed for that occurrence. Updating a shortcut does not alter
old logs.

A mixture is a log item whose version contains ordered component references to
other log-item versions and their quantities. It has no fabricated source nutrient
row. Its consumed-nutrient projection is the deterministic interval-preserving sum
of the components' scaled resolutions. An unknown component contribution keeps the
mixture contribution unknown for that nutrient.

## 3. Evidence, assertions and decisive identity

`capture_evidence` records what was obtained, not what the system concluded. Each
record contains:

- `evidence_id`, `kind`, `captured_at`, `locale` and `sha256` where bytes exist;
- the original barcode value and symbology, original text, or original panel value
  and basis, as applicable;
- the capture mechanism and its version;
- a local attachment reference when raw media is retained; and
- no nutrient value invented by parsing, matching or augmentation.

Raw photographs/crops, OCR bounding boxes and alternatives, scanner frames,
transient audio and provider diagnostics remain local-only. The canonical JSON may
contain their hashes, times, kinds and verified extracted assertions, but not the
raw media. Audio follows the existing no-persistence rule.

Parsing creates assertions which cite evidence. A correction creates a new
assertion with `supersedes_assertion_id`, author (`user` or a named process), time
and reason. Rejected assertions remain auditable. Assertions do not mutate evidence.

Every product or log-item version represents the following attributes explicitly;
`unknown` is valid and blocks any candidate for which compatibility depends on it:

| Attribute | Contract |
| --- | --- |
| Preparation | `as_sold`, `raw`, `cooked`, `reheated`, named method, or `unknown`; method and yield basis are retained |
| Bone state | `with_bone`, `boneless`, `not_applicable`, or `unknown` |
| Skin state | `skin_on`, `skinless`, `not_applicable`, or `unknown` |
| Drained state | `drained`, `undrained`, `not_applicable`, or `unknown` |
| Packing medium | named value such as `olive_oil`, `oil`, `brine`, `water`, `sauce`, `none`, or `unknown` |
| Fortification | `fortified`, `unfortified`, or `unknown`, plus named declared fortificants when known |
| Serving basis | `per_100_g`, `per_100_ml`, `per_serving`, `per_unit`, or a named prepared/drained basis |
| Edible quantity | exact amount in `g`, `mL` or count plus the evidenced conversion; package mass and edible mass are separate |

Volume must not be converted to mass without a named density value, unit, source and
release. Net quantity must not substitute for drained or edible quantity. A count or
household measure must retain the conversion version that produced grams or
millilitres.

## 4. Item classification

`item_class` is one of:

- `food`: an unfortified food or dish;
- `fortified_food`: a food or drink with declared added fortificants;
- `supplement`: a supplement occurrence explicitly recorded as taken;
- `drink`: a non-water beverage that is not classified as fortified food; or
- `water`: plain water.

Classification describes the consumed item, not confidence or nutrient evidence.
Fortified food is distinct because declared fortificant values may be `measured`
while intrinsic nutrients are `augmented`. A fortified drink is
`fortified_food`, not simultaneously `drink`. Water containing added nutrients or
other ingredients is not `water`. A scheduled supplement that is skipped or
unconfirmed is not a consumed log item and contributes no assumed nutrients.

## 5. Nutrient catalogue and canonical units

The food ledger reuses the current `NutritionCatalogue` keys and export units
without aliases. Conversion into these units is owned by the ingestion/resolution
boundary; source values and units are also retained. This contract does not change
the current HealthKit query catalogue. The exact serialized unit tokens are `mcg`
and `mL`; these resolve the research report's typographic `µg` and `ml` wording in
favour of current repository compatibility.

| Key | Canonical unit | Key | Canonical unit |
| --- | ---: | --- | ---: |
| `energy_consumed` | `kcal` | `carbohydrates` | `g` |
| `protein` | `g` | `fat_total` | `g` |
| `fat_saturated` | `g` | `fat_monounsaturated` | `g` |
| `fat_polyunsaturated` | `g` | `fiber` | `g` |
| `sugar` | `g` | `cholesterol` | `mg` |
| `vitamin_a` | `mcg` | `thiamin_b1` | `mg` |
| `riboflavin_b2` | `mg` | `niacin_b3` | `mg` |
| `pantothenic_acid_b5` | `mg` | `vitamin_b6` | `mg` |
| `biotin_b7` | `mcg` | `folate_b9` | `mcg` |
| `vitamin_b12` | `mcg` | `vitamin_c` | `mg` |
| `vitamin_d` | `mcg` | `vitamin_e` | `mg` |
| `vitamin_k` | `mcg` | `calcium` | `mg` |
| `chloride` | `mg` | `iron` | `mg` |
| `magnesium` | `mg` | `phosphorus` | `mg` |
| `potassium` | `mg` | `sodium` | `mg` |
| `zinc` | `mg` | `chromium` | `mcg` |
| `copper` | `mg` | `iodine` | `mcg` |
| `manganese` | `mg` | `molybdenum` | `mcg` |
| `selenium` | `mcg` | `water` | `mL` |
| `caffeine` | `mg` |  |  |

kJ and kcal are alternate energy representations, never additive nutrients. The
canonical energy amount is kcal, while original kJ and the conversion version are
retained. A declared salt value may deterministically produce sodium using
`sodium = salt / 2.5`; the salt declaration, its basis and the transform ID must be
retained. The result is not relabelled as directly observed sodium.

## 6. Nutrient value contract

Each resolution version contains exactly 39 entries in catalogue order. A nutrient
entry has this logical shape:

```json
{
  "key": "sodium",
  "state": "measured",
  "resolution_status": "resolved",
  "basis_amount": {"value": 240.0, "unit": "mg"},
  "source_value": {
    "value": 0.6,
    "unit": "g_salt",
    "basis": {"kind": "per_100_g", "quantity": 100.0, "unit": "g"}
  },
  "provenance": [{
    "source_kind": "user_verified_panel",
    "evidence_id": "<uuid>",
    "source_id": "physical_package",
    "source_release_id": "package:<evidence uuid>",
    "record_id": null
  }],
  "transforms": [{"transform_id": "salt_to_sodium_v1"}]
}
```

The states mean:

- `measured`: an exact scalar declared or observed for the exact item and basis.
  It includes a user-entered or verified package declaration; it does not claim a
  laboratory assay or biological exactness.
- `augmented`: an exact scalar estimated from a matched generic record, compatible
  product record or explicit reconstruction. It always names the source record,
  immutable source release and method/match version.
- `bounded`: an interval rather than an exact scalar. It contains `lower`, `upper`,
  `lower_closed`, `upper_closed`, and `bound_origin` (`measured` or `augmented`). A
  missing endpoint is represented as absent, not infinity.
- `unknown`: no defensible amount. It has no amount or interval and contains a
  reason such as `not_declared`, `no_compatible_source`, `missing_conversion`, or
  `conflicting_evidence`.

`resolution_status` is `resolved` or `conflict`. A conflict retains all candidate
values and provenance under `conflict_candidates`. Its effective `state` must be
`unknown` with reason `conflicting_evidence` until an explicit assertion resolves
it. Resolving a conflict creates a new resolution version and cites the selected and
rejected candidates; it does not delete them.

`basis_amount` is the value on the resolution's named per-100-g, per-100-mL,
per-serving, per-unit, drained/as-prepared or other basis, in the catalogue's
canonical unit. `source_value` preserves the original declaration/dataset value and
unit. A log-item projection scales `basis_amount` by its separately versioned edible
quantity and records the resulting `amount`; it does not create new source evidence.
This separation prevents later quantity edits from being mistaken for a new source
or resolution.

## 7. Provenance and immutable releases

Every non-unknown value must carry provenance. A provenance entry contains:

- `source_kind`: `user_verified_panel`, `manual_declaration`,
  `exact_product_dataset`, `generic_composition_dataset`, or
  `recipe_reconstruction`;
- `source_id`: stable dataset/provider/physical-evidence identity;
- `source_release_id`: immutable dated release, manifest hash or evidence-scoped
  release ID;
- `record_id` within that release, when applicable;
- `evidence_id` for physical/manual evidence, when applicable;
- capture/retrieval time and, for mutable remote results, a response hash;
- licence/attribution manifest reference for distributable datasets;
- match decision, user-confirmation assertion and their versions; and
- every deterministic transform and conversion version.

For a dataset release, `source_release_id` must resolve to a manifest containing the
source date/version, SHA-256 of the exact artefact or reduced derivative, schema
version, conversion pipeline version and attribution. A reduced local corpus has its
own release ID and also names its upstream release. Dataset rows use the compound
identity `(source_release_id, record_id)`.

Model output is not source evidence. If a model extracts or ranks evidence, record
its `model_release_id`, prompt/feature version and decision, but the selected real
record and its source release remain the nutrient provenance.

## 8. Per-nutrient precedence and merge

After converting candidates to the same evidenced basis and edible quantity, apply
this precedence independently to each nutrient:

1. user-verified current physical-package declaration for the exact item and basis;
2. exact-product declared value from a version-compatible immutable source release,
   labelled `measured` only when exact item/formulation compatibility is established;
3. supported recipe/reconstruction estimate, labelled `augmented`;
4. accepted compatible generic-composition record, labelled `augmented`;
5. `unknown`.

Precedence is usable only when identity and basis are compatible. A higher-ranked
value with an unknown or contradictory decisive attribute is ineligible; it does
not suppress a compatible lower-ranked value. A physical panel value applies only
to the nutrient actually printed. It cannot make unprinted nutrients measured.

The merge algorithm is:

1. Preserve every candidate and its provenance.
2. Reject candidates with a hard identity/basis contradiction, recording reason
   codes.
3. Convert eligible candidates using named deterministic transforms. If a required
   quantity, density or serving conversion is missing, the candidate cannot produce
   an amount.
4. Select the sole highest-precedence compatible candidate.
5. If candidates at that winning level disagree beyond exact deterministic
   conversion/rounding compatibility and no assertion adjudicates them, emit an
   explicit conflict and effective `unknown`.
6. Record lower-precedence candidates as non-selected; never overwrite them.

Bounds combine through interval arithmetic. Exact values are zero-width intervals
for calculation only. Add lower endpoints and upper endpoints separately, retaining
open/closed semantics. If any consumed component is unknown for a nutrient, a daily
summary may report the known subtotal and bounds over known/bounded inputs, but
`has_unknown_contribution` must be true and the result must not be labelled the
whole-day total.

## 9. Correction, reformulation and re-resolution

- **Evidence correction:** evidence never changes. Add a correcting assertion and a
  new affected entity/resolution version.
- **Log correction:** retain `log_item_id`; create a new `log_item_version_id` with
  `supersedes_log_item_version_id` and a reason. Derived summaries create new
  versions. The old log version remains reproducible.
- **Product reformulation:** retain `product_id` only when it is genuinely the same
  market identity; create a new product version with effective/capture evidence.
  Old logs keep their old product version. An unchanged barcode does not collapse
  the versions.
- **Source correction/update:** install a new immutable `source_release_id` beside
  the old one. Existing resolutions remain reproducible against the old release.
- **Retrospective re-resolution:** it is opt-in and creates a new
  `resolution_version_id` with `supersedes_resolution_version_id`, trigger, time,
  algorithm/model version and source releases. The log's
  `original_resolution_version_id` never changes. A new log/summary materialisation
  may name the new `effective_resolution_version_id` and must provide a before/after
  diff. No original evidence, product version or prior result is rewritten.

An automatically discovered re-resolution may be stored as a proposal, but it is
not effective until the later #101 contract's confirmation rule is satisfied.

## 10. Canonical JSON and privacy boundary

### Local-only

The live database, raw panel/package images, OCR geometry and rejected candidates,
scanner frames, local search indices, transient audio, provider diagnostics,
credentials, Keychain material and internal operation metadata remain local-only.
Local retention/deletion details belong to #90; this contract fixes only the data
boundary.

### Canonical food JSON

The canonical food projection contains:

- contract/schema version and deterministic snapshot identity;
- product, library, log, resolution and summary stable/version IDs needed to
  reproduce the snapshot;
- verified identity attributes and edible quantities;
- evidence descriptors/hashes, assertions and correction/supersession links;
- all 39 nutrient states, bounds, explicit unknown reasons and conflicts;
- item classification, source releases, record IDs, transforms and match/user
  decisions; and
- summary known subtotals, interval over accounted inputs,
  `has_unknown_contribution`, `by_item_class` and `by_evidence_state` splits, and
  exact input version IDs.

It excludes raw evidence media and secrets. A consumer must be able to distinguish
the state split without consulting the local database.

### Later HealthKit eligibility

Nothing in this contract authorises a write. A future separately approved HealthKit
plan may consider a nutrient eligible only when it is a finite exact scalar in
`measured` or `augmented` state, has no conflict, has an evidenced consumed quantity,
uses a HealthKit-compatible unit and is part of an explicit user-invoked save.
`bounded`, `unknown`, unconfirmed supplement events and unresolved mixtures are not
eligible. Provenance, state and item-class distinctions remain canonical JSON data
even if an eligible combined scalar is later written.

## 11. Existing daily-export migration

The current production daily JSON is schema v3. Its `today.nutrition` and
`app_context.nutrition` are source-filtered HealthKit aggregates with
`available`/`no_data_or_access` states. They are not item-level food evidence and
must not be reinterpreted as this ledger.

When implementation is separately authorised, the first food-aware daily export
must be additive **schema v4**:

- retain every v3 field and its meaning unchanged;
- add `today.food_log` for the canonical item/resolution projection and
  `today.food_nutrition_summary` for its state-preserving 39-nutrient summary;
- keep the existing `today.nutrition` and `app_context.nutrition` names exclusively
  for the legacy read-only HealthKit-source view until a separate migration plan
  retires them;
- include `food_contract_version: 1` inside the food projection;
- never derive item provenance by subtracting or reverse-engineering HealthKit
  totals; and
- allow a v4 snapshot to replace a verified v1/v2/v3 same-date canonical Drive file
  under the same persisted file ID, retaining stale-cutoff rejection, exact-byte
  readback and one-file-per-reporting-date identity.

Readers must reject an unsupported newer major schema rather than ignore unknown
food semantics. Additive optional fields within v4 require a documented minor
contract version. Changing a state meaning, unit, identifier rule or required field
requires a new daily schema version and migration fixtures. Migrations are pure,
deterministic and preserve the original bytes or hash plus the originating schema
version. No in-place destructive migration is permitted.

The v4 shape is frozen here for dependency planning only. #90 chooses persistence
and backup mechanics; #94 must create production schemas and fixtures under its own
authority.

## 12. Worked examples

The example numbers are structural illustrations, not dietary guidance.

### Sardines with bone versus boneless

1. Evidence A says “sardines in oil, drained, with bone”; evidence B says
   “boneless sardine fillets in oil, drained”. They create different product IDs
   because bone state and form are decisive identities.
2. A generic row explicitly describing drained solids with bone is compatible only
   with A. Its calcium can be `augmented` with release/record provenance.
3. The same row is a hard contradiction for B. If B has no compatible calcium
   evidence, B's calcium is `unknown`; the system does not borrow A's calcium.
4. Both logs retain their exact product/resolution versions, quantity conversions
   and rejected-candidate reason `bone_state_conflict`.

### Drained versus undrained canned food

1. Capture retains net mass, declared drained mass, packing medium and whether that
   medium was consumed.
2. A 100 g `drained` log may use a composition row whose basis is drained solids.
3. An `undrained` log cannot use that row for the whole consumed quantity unless an
   evidenced component resolution accounts separately for solids and medium.
4. Missing drained/medium quantities block conversion and produce `unknown`, not an
   estimate from net pack weight.

### Fortified versus unfortified food

1. Fortification state is a hard matching attribute. An unfortified generic cereal
   row cannot supply declared vitamin D for a fortified product, and a fortified row
   cannot supply it to an unfortified product.
2. For a fortified product, user-verified declared vitamin D is `measured`.
   Compatible generic intrinsic magnesium may independently be `augmented`.
3. The item class is `fortified_food`; the two nutrients retain their different
   states and sources.

### Product reformulation

1. Two packages share a GTIN but have different panels/ingredients at different
   capture dates.
2. The second package creates product version 2 and a new resolution version. A
   sodium disagreement is retained as reformulation evidence, not overwritten by
   the newer database response.
3. An old log remains linked to product version 1 and its original resolution. A
   new log uses version 2. If the applicable formulation date is ambiguous, the
   affected nutrient is an explicit conflict/unknown pending confirmation.

### Bounded label value

1. A verified label says sugar `<0.5 g per serving`.
2. Store `state: bounded`, `bound_origin: measured`, lower `0` closed and upper
   `0.5` open, plus serving definition and evidence.
3. Two such servings contribute `[0, 1.0)` g. They do not contribute `0`, `0.5` or
   `1.0` g as an exact value and are not later HealthKit-eligible.

### Nutrient remains unknown

1. A physical label does not declare iodine and no compatible generic row survives
   the identity gates.
2. Iodine is `unknown` with reason `no_compatible_source`; no `basis_amount` or
   consumed `amount` is emitted.
3. The daily summary reports its known iodine subtotal from other items and
   `has_unknown_contribution: true`. It does not call that subtotal the daily total.

### Later dataset/model re-resolution

1. A log originally used `cofid-2021:<record>` through resolution version 1.
2. A later immutable dataset or matcher release proposes another compatible row.
3. The proposal cites the old and new releases, algorithm/model version and a
   nutrient-level before/after diff. Original capture evidence, product version and
   resolution version 1 are untouched.
4. If accepted under the later #101 policy, resolution version 2 supersedes version
   1 for a new effective materialisation. The log still exposes
   `original_resolution_version_id` and historical summaries remain reproducible.

### Mixture with an unknown component

1. A bowl log references immutable yoghurt, fruit and topping log-item versions.
2. Protein is the sum of compatible exact/interval component values with each
   provenance chain retained.
3. If the topping's selenium is unknown, the bowl and day expose the accounted
   selenium subtotal and `has_unknown_contribution: true`; no complete scalar is
   fabricated.

## 13. Dependency gates

- #87 may now freeze fixtures using these nutrient keys, decisive attributes,
  source/release IDs, provenance kinds and unknown/conflict reasons. It must measure
  actual source artefacts and must not redefine the contract.
- #90 may now choose the local database, operation log, snapshot, conflict and Drive
  backup protocol using these stable/version IDs and immutable relationships. It
  must not change the domain semantics or use Drive as the live store.
- #94 remains blocked by accepted outcomes from #87 and #90 and must be decomposed
  before implementation. It owns the eventual application/schema changes, not #89.

## 14. Deliberately unresolved evidence questions

No domain-semantic decision required by #89 remains open. The following measured or
implementation choices remain with their named issues:

- #87: actual CoFID/OFF artefact shape, coverage, completeness, licence fit and
  immutable release-manifest values;
- #90: database technology, operation-log format, retention/deletion, backup
  packaging, device identity and conflict-resolution UX;
- #92/#98: matching model, calibrated threshold and promotion evidence;
- #101: user confirmation and adoption UX for retrospective re-resolution; and
- #97: any HealthKit-write permission, reconciliation, deletion and physical-device
  acceptance protocol.
