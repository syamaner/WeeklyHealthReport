# Proposed optional HealthKit projection and export migration

Issue #97 · 26 September 2026 · **proposed, not ratified**

This document is a design deliverable only. It does not enable writes, alter
permissions, run a device, or authorise implementation. The app remains read-only
with an empty HealthKit `toShare` set. Local, versioned food JSON stays canonical.
Ratifying the plan, approving implementation, and approving a concrete device run
are separate decisions. #97 remains open until its required evidence and ratification.

## Decision proposed for ratification

Use optional **per-log-item dietary quantity samples**, one sample per eligible
nutrient, rather than food correlations or a second set of daily-total samples.
Use the recorded consumption instant as start/end, not the time of export. This
avoids synthesising a meal interval and lets correction/deletion address one
logged item. Preserve the ledger reporting date/calendar alongside the intent;
cross-time-zone HealthKit bucketing is a documented comparison difference, not a
reason to move a historic consumption timestamp.

Apple supports both dietary samples and food correlations. Correlations group
related samples and are immutable; Apple generally expects an energy sample in a
food correlation. Many legitimate ledger entries have unknown energy. Omitting
correlations in the first projection avoids inventing that value, dual save paths
and unclear correlation membership during deletion. This is our conservative
design choice, not an Apple prohibition on other food shapes.
[Apple nutrition types](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers),
[HKCorrelation](https://developer.apple.com/documentation/healthkit/hkcorrelation).

No whole-day nutrition aggregate is saved alongside the per-item samples: that
would count the same contribution twice. Do not infer missing item quantities from
the current HealthKit totals or reverse-engineer another app's food entries.

## Eligibility and reconciliation contract (proposed v1)

A pure planner consumes an immutable canonical snapshot and an explicit selected
set of current log-version IDs. It produces proposed sample intents and structured
omissions; it cannot call HealthKit. For each log and nutrient:

1. The effective resolution, confirmed product identity, consumed quantity and
   every required quantity/basis conversion must be evidenced and unambiguous.
2. Include only finite, non-negative exact `measured` or `augmented` contributions,
   with no unresolved conflict. Keep the state/provenance distinction in JSON.
3. Combine eligible contributions **within this log and nutrient** only when all
   contributions are accounted for. An unresolved mixture, unknown contribution,
   interval, or unconfirmed supplement dose prevents a scalar for that entry.
4. Verify semantic as well as dimensional compatibility with the target. Matching
   mass units alone does not prove that vitamin equivalents or chemical forms are
   interchangeable. Unapproved IU/equivalent/form transforms are omitted with a
   reason; no implicit conversion is introduced here.
5. A genuinely evidenced exact zero is different from no data. Never replace an
   omission with zero, a midpoint, a limit, or the known portion of an incomplete
   item. Type availability or permission failure is an explicit omission/failure.

For every nutrient, `writeable_subtotal` is the sum of the proposed eligible
per-item intents. It is **not** necessarily the full daily food total. Record
eligible/omitted log-version IDs, omission reasons and `has_omitted_contribution`.
After exact readback, the app-owned samples for this intent must reproduce the
same subtotal within a ratified unit-conversion tolerance. Record both source
numbers and converted values; do not silently round display text into stored data.
Existing measured/augmented/bounded/unknown summaries remain unchanged.

Illustrative synthetic cases, not executed HealthKit tests:

| Selected input | Proposed result |
| --- | --- |
| One fully resolved item: 10 g measured + 2 g augmented protein | One 12 g protein sample; JSON retains the two evidence states |
| One mixture: 10 g known protein plus unknown ingredient protein | No protein sample for that mixture |
| Item A has 10 g exact protein; separate item B has unknown protein | A contributes 10 g; B is omitted; daily writeable subtotal is explicitly incomplete |
| Sugar is `[0, 0.5)` g | Omit sugar, never write 0 or 0.25 g |
| Water is an evidenced exact 0 mL | Eligible zero, subject to supported-type/device validation |
| Vitamin D is declared in IU without an approved form conversion | Omit, even if other nutrients are eligible |

## Candidate type map

These are the existing read catalogue's 39 mappings, proposed for reuse at the
adapter boundary. This table establishes representation, **not unconditional
write eligibility**. Each identifier must exist on the supported OS and pass the
per-value gates above before being requested or saved. `mcg` means micrograms;
the adapter uses HealthKit mass/volume/energy units, not a stringly typed value.

| Canonical key | HKQuantityTypeIdentifier member | Canonical output unit |
| --- | --- | --- |
| energy_consumed | dietaryEnergyConsumed | kcal |
| carbohydrates | dietaryCarbohydrates | g |
| protein | dietaryProtein | g |
| fat_total | dietaryFatTotal | g |
| fat_saturated | dietaryFatSaturated | g |
| fat_monounsaturated | dietaryFatMonounsaturated | g |
| fat_polyunsaturated | dietaryFatPolyunsaturated | g |
| fiber | dietaryFiber | g |
| sugar | dietarySugar | g |
| cholesterol | dietaryCholesterol | mg |
| vitamin_a | dietaryVitaminA | mcg |
| thiamin_b1 | dietaryThiamin | mg |
| riboflavin_b2 | dietaryRiboflavin | mg |
| niacin_b3 | dietaryNiacin | mg |
| pantothenic_acid_b5 | dietaryPantothenicAcid | mg |
| vitamin_b6 | dietaryVitaminB6 | mg |
| biotin_b7 | dietaryBiotin | mcg |
| folate_b9 | dietaryFolate | mcg |
| vitamin_b12 | dietaryVitaminB12 | mcg |
| vitamin_c | dietaryVitaminC | mg |
| vitamin_d | dietaryVitaminD | mcg |
| vitamin_e | dietaryVitaminE | mg |
| vitamin_k | dietaryVitaminK | mcg |
| calcium | dietaryCalcium | mg |
| chloride | dietaryChloride | mg |
| iron | dietaryIron | mg |
| magnesium | dietaryMagnesium | mg |
| phosphorus | dietaryPhosphorus | mg |
| potassium | dietaryPotassium | mg |
| sodium | dietarySodium | mg |
| zinc | dietaryZinc | mg |
| chromium | dietaryChromium | mcg |
| copper | dietaryCopper | mg |
| iodine | dietaryIodine | mcg |
| manganese | dietaryManganese | mg |
| molybdenum | dietaryMolybdenum | mcg |
| selenium | dietarySelenium | mcg |
| water | dietaryWater | mL |
| caffeine | dietaryCaffeine | mg |

Implementation must compare this map to `NutritionCatalogue` and
`NutritionQueryCatalogue`, failing for duplicate, missing or unsupported mappings.
Do not assume that an existing read mapping proves a source-form conversion is
valid for writing.

## Identity, amendment and deletion

Maintain a protected local projection journal separate from immutable food history.
Each intent pins the canonical snapshot hash, source log/resolution versions,
planner version, exact payload, writer namespace and local revision. Inject IDs,
clock, canonical encoding and hashing. Persist the prepared intent before calling
the adapter. No queue is drained automatically after restart or in the background.
Send only scalar sample data and the minimal opaque reconciliation metadata. Raw
captures, receipt text, personal notes and the full canonical document do not
belong in HealthKit metadata.

Proposed sync key: `food-projection-v1:<writer-namespace>:<log-id>:<nutrient-key>`.
The writer namespace is installation-owned and never silently adopted from an
imported food archive. Increment a monotonic integer revision for an explicitly
accepted changed projection; an identical retry retains both version and payload.
It is not the dataset version or a timestamp. Refuse divergent same-version payloads.
Apple's sync identifier must be paired with a sync version; a higher version can
replace an existing object with the same identifier.
[Apple sync identifiers](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier).

Treat installation loss, restored archives and multi-device takeover as recovery
boundaries: imports do not replay HealthKit writes. Do not assume global
cross-device idempotency from sync metadata alone. A future takeover protocol must
prove namespace ownership and exact prior output before enabling amendments.

Record returned/read-back sample UUIDs and source revision. Before amendment or
deletion, resolve exact journal-owned identities and verify type, sync key/version,
namespace and app source. Never delete by date alone, by nutrient type alone, by
food name, or by an imported unverified UUID. Apple limits deletion to objects this
app saved; that is necessary but broader than this feature's ownership boundary.
Revoked sharing permission can also prevent deletion.
[Apple deletion rules](https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects(of:predicate:withcompletion:)).

Corrections/re-resolution change only an explicitly accepted downstream projection.
If a formerly exact nutrient becomes unknown, the preview lists the old owned
sample for removal rather than retaining a now-misleading scalar. Show additions,
replacements and removals before acceptance. Cross-call save/delete/readback is not
assumed atomic: journal `prepared`, `applying`, `unverified`, `verified` and
`recovery_required` states. On ambiguous completion, do not blindly replay or report
success; reconcile the exact identities on an explicit retry. An interrupted mixed
operation stays visibly incomplete until all expected outputs and removals match.

Rollback means an explicit new compensating projection (higher versions and/or
exact owned deletions), never rewriting the ledger or promising to rewind an
external store atomically. Loss of ownership evidence or revoked permission stops
automatic repair and requires user-directed recovery. Neither an empty query nor
missing metadata is permission to recreate/delete unknown objects.

## Source-filtered reporting and migration

Keep the current `fetchNutrition` source predicate and daily-first statistics.
Do not auto-select this app when its source first appears; retain the user's saved
source bundle identifier and existing no-fallback behaviour. Never sum canonical
food totals with HealthKit totals: the same event may be present in both.

The existing schema-v4 food projection already adds canonical food data without
reinterpreting schema-v3 `today.nutrition` or `app_context.nutrition`. Preserve that
meaning. A future writer-aware daily **schema v5** is proposed to add a versioned
`today.food_healthkit_projection` envelope containing intent identity, writeable
subtotals, omissions and verification status. It must not rename legacy fields or
claim that the selected external HealthKit source equals the local food ledger.
The exact new schema requires ratification and synthetic golden fixtures before
implementation; v4 is not silently extended with unversioned write metadata.

Consumers choose the canonical food fields for provenance, intervals and source/
item-class splits; the legacy fields remain an explicitly selected HealthKit view.
Readers must reject unsupported major versions. Old exported bytes stay historical;
a later explicitly reviewed export may supersede the same-date destination only
under the existing identity and readback contract. This plan authorises no Drive
contact and does not make inventory import mandatory.

## User invocation and permission UX

The feature defaults off. A preview first shows selected entries, exact source
versions, scalar amounts, omitted nutrients, pending removals and incomplete totals.
Only a separate explicit action requests sharing permission for the precise types
that will be used. A successful permission request is not proof every type was
granted; inspect per-type sharing status and retain explicit partial/failure states.
No scheduled write, background migration, automatic re-resolution publish or
permission prompt on ordinary food entry is introduced.

Read denial remains undisclosed by HealthKit. An empty result is no visible data/
access, never proof of zero or absence of another source. Apple distinguishes
sharing status from read visibility.
[Apple authorization status](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus).

Before Save, state that HealthKit is a downstream scalar projection and may show
partial nutrition. During uncertain completion disable another competing publish
for the same intent. Provide explicit Retry/reconcile, Inspect and Cancel-before-
submission; do not call a possibly submitted operation cancelled/rolled back.

## Required evidence before any implementation promotion

Existing regression evidence: `DailyHealthExportTests` covers all 39 catalogue
units, sparse/empty states, source selection/no fallback, DST and additive v4
meaning. `FoodArchiveContractTests` covers deterministic projections, immutable
history and atomic import failure. These are prerequisites, **not writer tests**.

The [executable planning specification](../Tools/FoodHealthKitPlanning/README.md)
adds 10 standard-library-only synthetic tests: all 39 map entries and units,
exact arithmetic and omission propagation, duplicate/mixed-version rejection,
source/date filtering, readback equality and strict journal-owned removal
selection. These are invented-record model/predicate tests, not HealthKit calls,
real SDK predicates, durable-journal recovery or physical evidence. The reference
is not linked to the app and cannot save or delete data.

The separately authorised implementation must add a synthetic planner/adapter
contract suite for:

- Every map entry and source-form gate; grams/mg/mcg, mL and kcal conversion;
  evidenced zero versus absent; NaN/infinity/negative rejection; bounds/conflicts.
- Measured plus augmented exact sums, incomplete mixtures, unconfirmed supplements,
  partial daily coverage and equality of planned/readback writeable subtotals.
- Same-intent retry, divergent payload, increasing versions, stale ledger snapshot,
  concurrent publish, exact-to-unknown removal and declined preview with no calls.
- Wrong namespace/source/UUID, imported/foreign entries, missing journal, revoked
  permission and no broad deletion; crash points between every journal/API step.
- Query predicates that preserve the selected source, include only the intended
  owned objects during reconciliation, and respect reporting windows/DST.
- Schema-v3/v4 golden stability, v5 round trip/unknown-version rejection and no
  replacement of a prior export merely because a food resolution changed.

Then run simulator tests and static analysis. Only after concrete device/account,
data, recovery and stop conditions are separately approved: install a signed build,
use invented entries, review exact types/amounts, save, read back exact identities,
correct, remove and test permission revocation/interruption. Compare the selected
source and canonical JSON without adding them. Signing/install proves none of
these live outcomes. Never test on unrelated existing HealthKit objects.

## Ratification checkpoint

Decisions requested later: quantity-only per-item shape; strict per-nutrient
eligibility; installation-owned sync/journal recovery; source-isolated reporting;
new v5 projection envelope; and staged implementation/device authority. Until
ratified, retain this proposal and #97 as open. No production writer, sharing
permission, live save/readback or deletion test has been implemented or performed.

Planning validation: all 39 identifier/unit rows match the Swift read catalogue;
the 10 executable planning tests pass and are checked in CI. No Swift production
code changed, so no additional local app build was needed. The remaining adapter,
permission, crash-recovery and schema-v5 tests above are still future work, not a
claim that a production writer has been implemented or validated.
