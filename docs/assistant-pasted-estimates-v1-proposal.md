# Assistant-pasted estimates v1 (contract)

Status: **accepted by the owner on 16 November 2026, after one local review and one round of blind
reviews (section 14). Not implemented.** Proposed the same day; section 12 records the owner's
eight decisions. The file keeps its original name so that existing links hold. Documentation
only: no app code, skill code or fixture changes with this document, and `privacy-and-egress.md`
is edited only by the implementing change. Implementation is a later phase with its own issue and
architecture gate, after daily export v2 and the estimates v2 phase. Section 14 says plainly what
has and has not been reviewed. It has no issue of its own yet and closes nothing. Programme #424.

It is a delta on [estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md)
(accepted 16 November 2026, not implemented), called "estimates v2" below, and through it on
[approved estimates v1](personal-food-catalogue-estimates-v1.md). It repeats neither. Everything in
those contracts that this one does not name stays as written. Where a number or a list would grow
(food contract, daily export version, the label list), this proposal takes the next free value and
says so. Acceptance added dated amendment notes to two accepted contracts: estimates v2 sections 3.3 and 5, for the lowered tier of section 5.3
(decision A4, decided), and daily export v2, for version 4 (section 9).

## 1. What this adds, and what it does not

The owner's aim is to fill as much as possible with reasonable, labelled estimates, and the
fallback they described is "screenshot it and ask my agent". This route makes that fallback a
journey on Confirm, in the "values too" shape the owner chose on 16 November 2026:

1. Confirm offers **Copy prompt**. The prompt describes the food, lists what is known, estimated
   and unknown, and fixes the reply format.
2. The owner pastes it into their own assistant, outside the app, and pastes the reply back.
3. The app reads only the fixed block of the reply, strictly, and shows each suggestion as a row
   the owner ticks one by one. Nothing is ticked by default.
4. One Log action saves the ticked rows as a new kind of estimate, with the reply kept as evidence.

A reply may supply **values** for nutrients still unknown and a **suggested tier** for estimates the
entry already has. What it can never do:

- supply a measured value, or replace a label value, a catalogue estimate or a merged record's
  value;
- carry a tier above `medium` (amber);
- change the catalogue, the entry's identity, its basis or the amount eaten;
- authorise anything by itself: a row counts only after the owner ticks it and taps Log.

The app makes no network call for this. It never contacts an assistant, and it does not know or
record which assistant the owner used.

## 2. Scope

- **Route.** Confirm for a candidate from Your food database (import v2 or estimates v2 release)
  whose basis is `per_100_g` or `per_100_ml`. Other routes are not offered it in v1 (decision A3, decided).
  The reason is in the save path: reviewed web and label candidates are admitted only while the
  saved nutrients equal the verified source's (`FoodConfirmationService.save`, the
  `invalidReviewedSource` and `invalidPastedLabelSource` guards), so adding values there is a
  change to those verifiers, not an addition.
- **When it is offered.** New logs and reopened logs. Not on the re-resolution screen and not on
  the quick add sheet (section 8).
- **Depends on** a chain of two phases that have not landed. In code today the food contract is 9
  and the daily export is version 1. Daily export v2 comes first, then the estimates v2 phase (its
  provenance kind, capture manifest, leave-out state, labels, food contract 10 and daily export
  version 3), then this. It is a later phase with its own issue and a fresh architecture gate.

## 3. The prompt, `assistant-estimate-prompt-v1`

The prompt is built by one pure function from the Confirm state, in English, and is the same text
for the same state. **Copy prompt** opens a preview that shows the exact text; **Copy** on that
preview writes it to this iPhone's clipboard only, where it expires after ten minutes (the rule
Copy JSON already follows). The text is not editable in the app.

### 3.1 Contents

In this order. A line whose value does not exist is left out, never written empty.

| Part | Content | Source |
|---|---|---|
| Opening | Fixed sentences: what is asked, and that the answer is for the food as described | constant |
| `Request:` | 16 lower-case hex digits (section 3.3) | derived |
| `Food:` | the name shown on Confirm | candidate or correction |
| `Brand:` | the brand shown on Confirm, when there is one and the preview's **Include brand** switch is on (decision A1) | candidate or correction |
| `Variety:` | the variant shown on Confirm | candidate or correction |
| `State:` | the preparation state, in fixed words | confirmed identity |
| `Details:` | each decisive detail that is known, in fixed words: bone, skin, drained, packing medium (its text as stored), fortification and the nutrients declared as added | confirmed identity |
| `Basis:` | `per 100 g` or `per 100 ml` | candidate basis |
| Known values | one line per nutrient with a value that is not an estimate: key, value, canonical unit and one closed phrase for its source ("from the label", "from the product's Open Food Facts record", "from a food composition table") | the log being confirmed |
| Estimated values | one line per catalogue estimate that is kept: key, value, unit, "estimated" or "estimated from a similar food", and its tier | capture manifest |
| Missing values | one line per eligible nutrient (section 5.1): key and canonical unit | the log being confirmed |
| Rules | fixed sentences, below | constant |
| Reply format | the fixed block of section 4, with placeholders | constant |

The fixed rules tell the assistant to: answer per the stated basis only and never convert; use
exactly the unit shown for each nutrient (sodium in mg, never salt; energy in kcal, never kJ);
leave out any nutrient it cannot estimate and never write 0 for "unknown"; give `medium` or `low`
for each value, never anything higher; suggest a tier only for the listed estimated values and
only when it would be lower; not change a known value; and reply with exactly one block. They
contain no health, target or diet wording.

The fixed words for `State:` and `Details:` come from one closed table owned by the application
layer and pinned by the prompt version, not from Confirm's display copy, so a wording change on
Confirm changes neither the prompt nor a request code. Name, brand, variety and packing medium are
sent as stored, **including any words the owner typed when correcting them**.

**Never in the prompt:** the amount eaten, the time or date, notes, any other entry, totals,
health data, the barcode, pack size, shop, price, receipt text, entry, record or release
identifiers, source addresses, digests, and the catalogue's free-text states and assumptions
(those are private workspace text). The name is sent as Confirm shows it. Catalogue names can
come from receipt product titles, so a name may itself hold a brand, an own-brand shop word or a
pack size, and it still holds them with the switch off; the preview shows the exact text so the
owner sees that before copying.

### 3.2 Example (synthetic)

```text
I am logging a food and some of its nutrition values are missing. Please estimate them from
what you know about this kind of food. Answer for the food exactly as described below.

Request: 3f9a1c0e5b7d2a46
Food: Butter beans in water
Variety: tinned
State: canned
Details: drained
Basis: per 100 g

Known values, per 100 g. Do not change these:
- energy_consumed: 82 kcal (from the label)
- protein: 5.9 g (from the label)

Estimated values, per 100 g. You may suggest a lower quality for these:
- iron: 1.5 mg (estimated from a similar food, quality medium)

Missing values you may estimate, with the unit to use:
- fiber (g)
- potassium (mg)

Rules:
- Give values per 100 g only. Do not convert from a serving or a pack.
- Use exactly the unit shown. Sodium is in mg, not salt. Energy is in kcal.
- Leave out anything you cannot estimate. Never write 0 to mean unknown.
- quality is medium or low. Use low when you are unsure of the food or its state.
- Reply with exactly one block in this form. Text outside it is ignored.

<<<assistant-estimate-reply-v1
{"schema":"assistant-estimate-reply-v1","request":"3f9a1c0e5b7d2a46","basis":"per_100_g",
 "values":[{"nutrient":"<key>","value":<number>,"unit":"<unit>","quality":"<medium or low>"}],
 "tiers":[{"nutrient":"<key>","quality":"<medium or low>"}]}
>>>
```

The block in the prompt holds placeholders that are not valid JSON, on purpose: pasting the prompt
itself back is rejected (`not_json`), never read as a reply.

### 3.3 The request code

`request` is the first 16 lower-case hex digits of the SHA-256 of the canonical JSON of the
prompt's **subject**: prompt version, name, brand as printed (null when not printed), variant,
and the typed identity tokens (the raw values of preparation, bone, skin, drained, packing medium,
fortification and declared fortificants) with the basis. It hashes tokens, never display words.
One food therefore has at most two valid codes, with and without the brand; a paste is accepted
for either, and the capture records which prompt text it answers. It binds a reply to the food and details it was written for. It is not
a secret and proves nothing about who wrote the reply; the owner's tick is what counts. Known
values, estimates and the missing list are not in the subject, so leaving a value out does not
invalidate a reply. The amount is never in it.

## 4. The reply, `assistant-estimate-reply-v1`

### 4.1 The block

The block is the text between a line that is exactly `<<<assistant-estimate-reply-v1` and the next
line that is exactly `>>>` (leading and trailing white space on those two lines is ignored).
Everything outside the block is ignored: never parsed, never shown, never stored, and no hash of
it is kept.

Inside the block is one JSON object with exactly these keys:

| Key | Value |
|---|---|
| `schema` | literal `assistant-estimate-reply-v1` |
| `request` | the 16 hex digits from the prompt |
| `basis` | `per_100_g` or `per_100_ml`, equal to the entry's basis |
| `values` | array, may be empty, at most 39 rows; each exactly `{nutrient, value, unit, quality}` |
| `tiers` | array, may be empty, at most 39 rows; each exactly `{nutrient, quality}` |

- `nutrient` is a key of the app's nutrient inventory (`NutrientKey`, 39 keys).
- `value` is a JSON number: finite, not negative, never a string or a boolean.
- `unit` is that key's canonical unit, spelt exactly (`kcal`, `g`, `mg`, `mcg`, `mL`).
- `quality` is `medium` or `low` on a value, and `high`, `medium` or `low` on a tier row (a tier
  row can only lower, section 5.3, so `high` there is read and then not offered).
- Every string in the block is at most 40 characters from `a` to `z`, `0` to `9`, `_` and `-`
  (`unit` may also hold `L`). Anything else is a fault of shape (`keys`) and rejects the whole
  reply, so the stored block can hold no sentence, name or address.
- There is no free-text field, no per-serving field, no conversion and no field for a source,
  link or comment. A new field is a new schema version.

### 4.2 Strict parsing, `assistant-estimate-parser-v1`

One pure function from the pasted text and a closed **parse context** to either a rejection or a
list of rows. The context is the parser's only view of the log, and it is stored in the capture so
that verification can reproduce every row code from the capture alone (section 6.2). It holds the
entry's basis, the valid request codes, and for each of the 39 keys exactly one class:
`eligible`; `stronger_source` (a label, Open Food Facts or merged record value, with the value
when the key is a parent); `catalogue_estimate` (with its tier, whether it is kept, and its value
when it is kept and the key is a parent); or
`not_fillable` (bounded, conflicting or unscalable). **A fault in the shape rejects the whole reply; a fault in one row's meaning rejects that
row and leaves the others.** Every rejection is shown to the owner in plain words, where the paste
was made. Nothing is repaired, guessed, rounded, converted or defaulted.

Whole-reply rejections, checked in this order (the first one found is shown):

| Code | When | Shown as |
|---|---|---|
| `empty` | nothing pasted | Nothing was pasted. |
| `too_long` | more than 20,000 Unicode scalars | The pasted text is too long. Paste only your assistant's reply. |
| `no_block` | no opening line, or no closing line after it | No reply block was found. Ask your assistant to answer in the format from the prompt. |
| `more_than_one_block` | a second opening line | More than one reply block was found. Paste a single reply. |
| `not_json` | the block is not one JSON object, or holds a repeated key | The reply block could not be read. |
| `keys` | a missing or unexpected key at the top level or in any row; a wrong JSON type anywhere (`value` not a JSON number, any other field not a string, an array or row of another type); a string outside the limits of section 4.1; or an array over 39 rows | The reply block has missing or unexpected fields. |
| `schema` | `schema` is another value | This reply uses a format this version of the app does not read. |
| `different_request` | `request` is not the code of the food and details now on Confirm | This reply was written for a different food or different details. Copy the prompt again. |
| `basis` | `basis` differs from the entry's | The reply is per 100 ml and this food is per 100 g. Values are never converted. (Or the reverse.) |
| `duplicate_nutrient` | a key twice in `values`, or twice in `tiers` | A nutrient appears more than once in the reply. |
| `nothing_usable` | both arrays empty, or every row rejected | The reply holds nothing that can be used here. (The row reasons are listed.) |

Row rejections (the row is listed under "Not used", with its reason, and cannot be ticked):

| Code | When | Shown as |
|---|---|---|
| `unknown_nutrient` | key not in the inventory | Not a nutrient this app records. |
| `unit` | a string that is not the key's canonical unit | Wrong unit: expected <the key's canonical unit>. Values are never converted. |
| `value` | a JSON number that is negative or too large to hold as a finite value | Not a usable number. |
| `impossible_value` | on a per 100 g entry, a mass above 100 g (in the key's unit), or energy above 900 kcal; on a per 100 ml entry, energy above 900 kcal | More than 100 g of the food can hold. (For energy: More energy than any food holds.) |
| `exceeds_parent` | saturated, monounsaturated or polyunsaturated fat above total fat, or sugar above carbohydrates, where the parent is a known value in the parse context, a kept catalogue estimate included | More than the total fat (or carbohydrate) of this food. |
| `not_fillable` | the key holds a bounded value, conflicting values or a value that cannot be scaled | This nutrient has more than one value or a range, and is not filled here. |
| `already_known` | the key has a value on the log from a label, an Open Food Facts record or a merged record | Already known from a stronger source. It is not replaced. |
| `has_catalogue_estimate` | the key has a catalogue estimate, whether kept, withheld or left out (decision A5) | This food already has a catalogue estimate for it. |
| `quality` | a string outside the list | Quality not recognised. |
| `tier_above_ceiling` | `high` on a value | An assistant's estimate cannot be rated above "some doubt". |
| `no_estimate` | a tier row for a key with no kept catalogue estimate | There is no estimate to rate. |
| `tier_not_lower` | a tier row equal to or above the estimate's tier | Not lower than the tier this estimate already has. Tiers are never raised here. |

So the two tables never compete: a field of the wrong JSON type is a fault of shape and rejects
the whole reply with `keys`, and the row codes `value`, `unit` and `quality` apply only to a field
of the right type with an unusable content.

Row codes are fixed when the reply is parsed and never depend on ticks. One further check is a
**tick rule**, not a row code, and is never stored: a child whose parent is another row of the
same reply cannot be ticked above that parent while the parent is ticked, and the later tick is
refused with the `exceeds_parent` wording. The save service is the authority: at Log it re-runs
eligibility, the ceiling, the bounds and the parent rule on the final nutrient set, and refuses a
state that fails, whatever the screen allowed. A row with an unknown key is listed by its position
in the reply ("Row 3"), since no text from the reply is rendered. The bounds are mechanical, not
a judgement of the food. Stated limits: no other arithmetic is checked (macronutrients are not
summed, energy is not recomputed); per 100 ml mass values have no bound because no density is
ever inferred; and water, in mL, has no bound on a per 100 g entry.

**A zero** is accepted as a value (decision A7) and its row and VoiceOver label say it in words ("none: 0 g"), so a zero is never ticked as if
it were a blank. The parser
cannot tell an estimated zero from a lazy one; the prompt forbids zero for unknown, each row is
ticked singly, and there is no "tick all".

**The reply is data.** Only closed tokens and numbers are read, no text from it is rendered as
copy, and nothing outside the block is looked at, so an instruction inside a reply has nowhere to
act.

## 5. Suggestions on Confirm

### 5.1 Which nutrients a value may fill

A value row is eligible only for a nutrient that, on the candidate as bound to Confirm, is
`.unknown` with status `resolved` and reason `not_declared` or `no_compatible_source`, **and** has
no catalogue estimate in the capture manifest. In code a conflict is also stored as `.unknown`
(reason `conflicting_evidence`, status `conflict`, with its candidates), and Your food database
candidates produce one when label values disagree; that key, and one with reason
`missing_conversion`, is never eligible. So:

- a label value, an Open Food Facts value and a merged record's value are never replaced;
- a catalogue estimate is never replaced, also when it was withheld (estimates v2 section 3.2) or
  left out by the owner. The eligible set is therefore fixed when the candidate is bound and does
  not move when a value is withheld, returns, is left out or is restored;
- a bounded value, conflicting values and an unscalable value are never filled (`not_fillable`):
  bounds stay bounds, and a reply never settles a conflict between label values.

### 5.2 Ranking, per nutrient

Estimates v2 section 4, with one rank added at the end:

1. a label value (`manual_declaration`, measured, or `exact_product_dataset`);
2. an approved estimate from the catalogue (composition table or page), augmented;
3. the merged generic record, for keys still unknown;
4. **an assistant estimate, for keys still unknown after 1 to 3** and never for a key that has a
   catalogue estimate in any state.

Because rank 4 fills only what 1 to 3 leave unknown, no nutrient ever has two contenders and there
is no last-write-wins case.

**An entry that has neither a label value nor a composition-table estimate.** Per nutrient, the
assistant estimate is then the only value for that key, always under its own label. Per entry: a
candidate with no known nutrient at all is not offered by search today and never reaches Confirm,
and that does not change. Assistant estimates belong to one log, never to the catalogue, so they
cannot make an empty entry visible, and they take no part in search, ranking, the fat partition or
escalation sufficiency. The route for an empty entry stays the catalogue build. On a log that does reach Confirm, a ticked assistant value does **not** satisfy estimates v2's
"Log needs one known nutrient" rule (decision A8): when withholding and leaving out leave no other
nutrient known, Log stays blocked with its reason, so a reply is never a log's only nutrition.

### 5.3 Tier suggestions for existing estimates (decision A4)

A ticked tier row **lowers** the tier shown for that catalogue estimate, for this log only. It
never raises one (the codec's ceilings rest on evidence a reply cannot supply), never changes the
value, its provenance bytes, the capture manifest, the ranking or the contradiction veto, and
never touches the catalogue. The lasting correction is the owner's review sheet at the next build.
A tier tick on a key that is then withheld or left out is cleared and never saved, so choices
evidence lists kept estimates only.

**Which tier governs.** Estimates v2 says the tier shown comes from the evidence record in the
capture manifest. This route adds one rule on top, as a dated amendment to that contract: the tier
shown and exported for a log is the manifest's, unless the effective resolution version's verified
choices evidence (section 6.3) names a lower tier for that nutrient, in which case it is that
lower one. The manifest stays the record of the tier the catalogue gave; a choices item that
fails verification, names a tier that is not lower, or belongs to another version is ignored, and
the manifest's tier is shown.

### 5.4 The ceiling and the visible label

- An assistant value is `medium` at most, enforced three times: the parser (`tier_above_ceiling`),
  the domain validation of the stored value, and the export validator. It is `NutrientValue.augmented`,
  never measured and never bounded.
- Two labels join the closed list of estimates v2 section 3.3: **"Estimated by your assistant, some
  doubt"** (amber) and **"Estimated by your assistant, rough"** (red). The colour marks the label,
  never the value, and never appears without its text; totals carry no tier.
- A lowered catalogue estimate keeps its own label at the lower tier, with "Tier lowered on your
  assistant's advice" in details.
- Details for an assistant value show: "Estimated by your assistant from the description of this
  food", the date pasted, and **View reply**, which shows the stored block as inert plain text.
- No health wording, target or classification appears with any of it.

### 5.5 The journey

- Confirm shows one section, "Ask your assistant", when the entry has at least one eligible
  nutrient or one kept catalogue estimate: **Copy prompt** and **Paste reply** (the system paste
  control, which reads the clipboard only when tapped).
- A rejected paste shows its reason in that section and changes nothing.
- An accepted paste shows "Suggestions from your assistant": one row per usable row, with the
  nutrient's name, the value and unit per 100 g or per 100 ml, the label it would carry, and a
  tick that starts off. Rejected rows follow under "Not used", each with its reason.
- Ticking a row adds the value to the nutrient list above with its label; unticking removes it.
  Each row is at least 44 pt, has a VoiceOver label that reads the nutrient, value, label and
  state, and never relies on colour.
- Pasting again asks first ("Replace the pasted reply? Your ticks will be cleared").
- Log stays the one save. Until Log nothing is stored, and a cancelled Confirm keeps nothing: the
  suggestion state (the pasted block, its capture and the ticks) is transient Confirm state that
  is never encoded with `FoodConfirmationState`, as `answersLabelFortification` is today.

### 5.6 When details or basis change after the paste

A reply is written for one subject. When a correction of details makes the current request code
differ from the reply's, or the basis changes, every tick is cleared, the rows cannot be ticked
and the section says "These suggestions were written for different details. Copy the prompt
again." If the details return to the reply's subject the rows can be ticked again, and they stay
unticked until the owner ticks them. A change of amount, time or a leave-out is not a change of
subject.

## 6. Stored shapes and evidence

### 6.1 Provenance kind `assistant_estimate`

A new `ProvenanceSourceKind.assistantEstimate` (raw value `assistant_estimate`). `approved_estimate`
is not reused: its fields name a catalogue release and a `pfe:` evidence record the owner approved
at build time, which is untrue here. Rules, in `NutrientEntry` validation:

- admitted only inside `.augmented`, never `.measured` or `.bounded`;
- `evidenceID` the reply capture's evidence; `responseHash` the capture payload's SHA-256;
  `manifestReference` `assistant-reply-capture-v1#<nutrient key>`; `transforms` empty; all required;
- its source release is one per capture, with `sourceID` `assistant-pasted-reply` and release ID
  `assistant-reply:sha256:<capture hash>`, committed with the log and linked from the resolution
  version like any other provenance release. That identifier stays on the device: the daily
  export writes a constant in its place (section 9). The phase gate pins the remaining required
  fields with truthful constants: the release's `releasedAt`, `artifactHash`, `schemaVersion`,
  `pipelineVersion`, `licence`, `attribution` and `manifestHash`, and the evidence's `locale` and
  `captureMethod`.

### 6.2 Reply capture `assistant-reply-capture-v1`

- **Content** (canonical JSON): `schema`, `prompt_version`, `parser_version`, `request`, the
  subject object, the exact prompt text that request code stands for, the **reply block verbatim**,
  the parse context of section 4.2, and each parsed row with its result code. No tick is in it.
  Only the block is kept, never the text around it and no hash of that text, and the block's
  strings are limited by section 4.1, so a stray paste of something else does not end up in the
  ledger.
- **When.** Built by a service call when a paste is accepted (the reducer stays pure and receives
  the finished capture in an action), with the evidence ID from `LedgerIDGenerating` and
  `capturedAt` from `LedgerClock`, because validation needs `evidenceID` and `responseHash` before
  any save. It is committed only with a Log whose saved version uses it (a ticked value or a
  lowered tier). A reply with nothing ticked is not stored.
- **Where.** Inline `CaptureEvidence`, kind `.labelText`, `originalPayload` `.text(<canonical
  JSON>)`, `byteHash` its SHA-256, `captureMethodVersion` `assistant-reply-capture-v1`, in the
  log's `LedgerMutation`. Other `.labelText` readers select by `captureMethodVersion` and ignore
  it, and its reader ignores theirs (one test each way, as for every `.labelText` kind).
- **How reopen finds it.** Through each assistant value's provenance `evidenceID`, and, for a
  version that holds no assistant value (ticks removed, or a tier lowered only), through the
  decision's embedded candidate, which carries the bound candidate's evidence IDs plus the
  capture's, appended last (readers that take the first evidence ID are unaffected): the
  mechanism estimates v2 section 5 defines for leave-out evidence. No stored type gains a field.
  Evidence IDs accumulate across versions, so **the current capture** is the one the effective
  version's assistant values cite; with none, the one its choices evidence names; with neither,
  the last one listed. Rows of any other capture are not shown.
- **Verification** on save and on reopen, in the application: the payload hash equals `byteHash`
  and each value's `responseHash`; the parser, re-run on the stored block against the stored
  parse context, returns the stored rows, and that context agrees with the decision's embedded
  candidate and the capture manifest; every saved assistant value equals a parsed row
  (key, value, unit, tier). A mismatch shows "Evidence not available" and never changes a stored
  value or its estimate state. A missing evidence row is a store integrity failure and the log
  does not load, as for any listed evidence.

### 6.3 Choices evidence `assistant-estimate-choices-v1`

Needed only for lowered tiers, since a ticked value is already visible in provenance. One item per
saved resolution version that lowers at least one tier: `schema`, the resolution version ID, the
reply capture's hash and the sorted list of `{nutrient, quality}`. Same kind, commit, reach and
verification as estimates v2's leave-out evidence, and the reader takes only the item whose
resolution version ID is the effective version's.

### 6.4 Table

No new `UnknownReason`, and no new stored raw value beyond `assistant_estimate`.

| Case | Stored value | Provenance | How reopen tells it apart |
|---|---|---|---|
| Assistant value ticked | `.augmented` | `assistant_estimate` | provenance; tier from the capture row |
| Suggested, not ticked | the candidate's own unknown value, unchanged (its reason is not rewritten) | none | the key is a usable row of the current capture; shown in details as "Suggested by your assistant, not used" |
| Suggested, never stored | the candidate's own unknown value, unchanged | none | no capture is cited; reads as any unknown |
| Catalogue estimate, tier lowered | `.augmented`, `approved_estimate`, bytes unchanged | unchanged | the key is in the effective version's choices evidence |

### 6.5 Saving

- The saved version's nutrients are the candidate's (or the correction's), with estimates v2's
  withheld and left-out keys unknown, and then the ticked assistant values on their eligible keys.
  The decision's embedded candidate keeps the source candidate's own nutrients; assistant values
  are never written into the candidate copy.
- The assistant selection (the cited capture, the ticked keys, the lowered tiers) joins estimates
  v2's one predicate, "the log's food facts changed", beside the leave-out set, and only where that
  predicate decides whether new records are written. A tick is **not** a correction: identity
  differences are still asked and recorded, the candidate decision's outcome is computed as for an
  uncorrected save, and on a reopened log a tick-only save carries the saved identity, decision
  record and outcome into the new assertion and decision. The assertion and edit reason texts are
  pinned in the phase gate.
- Today the save path writes evidence only for a new log (`newEvidence` is empty when `previous`
  is set) and new product records only when `previous == nil || correction != nil`. Committing a
  capture on a reopened log is therefore new work, shared with estimates v2's leave-out evidence.
- Nothing is selected or saved automatically, and an entry whose values are partly assistant
  estimates is not a generic estimate under `FoodConfirmationPolicy`.

## 7. Food contract and migration

`ProvenanceSourceKind` is a closed string enum, so an older build cannot decode the new kind.
Following estimates v2's allocation: **food contract 11**. `foodContractVersion` rises to 11; the
floor returns 11 for a record holding `assistant_estimate` provenance, `assistant-reply-capture-v1`
or `assistant-estimate-choices-v1` evidence, checked before the contract 10 rule, which is left as
it is; a metadata-only migration `v11_assistant_estimate` sets `food-ledger-v11`, and
`FoodLedgerGRDBStore.schemaVersion` and the store's open check accept it. An archive or
store holding none of the three keeps its contract and its bytes. If 11, daily export version 4 or
a name used here is taken when the phase starts, the phase takes the next free one and says so.

## 8. Other routes

Each route named by estimates v2, and what assistant estimates do on it.

- **A withheld catalogue estimate that returns.** Estimates v2 brings a withheld value back, with
  its label, when a correction of details removes the contradiction. That never meets an assistant
  value: a key with a catalogue estimate is not eligible in any state (section 5.1). The same
  correction changes the subject, so the reply's ticks are cleared under section 5.6; the returned
  catalogue estimate is unaffected by that, and a lowered tier on it is cleared with the other
  ticks.
- **A value the owner left out** stays out until undone, as estimates v2 says, and the reply cannot
  fill it. Leaving out is offered on catalogue estimates only; an assistant value is removed by
  unticking it, which stores nothing more than its absence.
- **Reopen** reads no network and no record. Saved assistant values show as saved, with the tier
  they were logged with. Unticking, ticking another usable row of the stored capture, or pasting a
  new reply each write a new version under section 6.5.
- **Re-resolution** (`FoodReresolutionService` and its screen, not Confirm) builds a fresh
  candidate from the active release and stores its nutrients. Assistant values and lowered tiers
  are **not carried**: the reply was written against the old values, and the fresh candidate may
  now hold its own. The screen shows "Estimates from your assistant are not carried over", beside
  the notice estimates v2 adds for leave-outs; the saved version stays as it is in the append-only
  record; copy and paste are not offered on that screen; and the new decision drops the capture and
  choices evidence IDs. The owner reopens the log to ask again.
- **Quick add and re-log always open Confirm** for an entry whose pinned or saved version holds an
  assistant value or cites a reply capture. Estimates v2 detects its own cases from the restored
  candidate; this one cannot be, because assistant values live in the saved version and not in the
  candidate, so it is detected from the version's provenance and the decision's evidence list.
  Quick add gains an ineligibility reason for it, and the save service refuses a one-step save of
  a state holding a capture. A new log built from a saved decision drops that decision's capture and
  choices evidence IDs, as estimates v2 does for leave-out IDs (today `relogInput` copies the
  saved candidate's evidence IDs whole). On the Confirm that opens, the earlier reply block is
  offered again when its request code matches the details carried, with every row unticked and
  the line "From your assistant's reply of <date>" (decision A6). It is parsed afresh against the
  new log's parse context, so a row may be classified differently from before, and a **new**
  capture is built from it; that capture joins the new log only when a row is ticked. With nothing
  ticked the new log cites no capture and keeps its contract. If the code does not match, the
  reply is not offered.
- **Daily totals** keep `includesEstimates`; a partial total stays a known minimum.
- **Search, the catalogue and import** are untouched. An assistant value never enters a catalogue
  file: the estimates schema has no truthful `source_type` for it, and adding one is a new schema
  version with its own contract.

## 9. Daily export, version 4

Estimates v2 defines version 3 as daily export v2's shape plus its estimate fields. **Version 4 is
version 3's shape plus the fields below**, recorded as a dated amendment to
[daily export v2](food-daily-export-contract-v2.md) when the phase lands, with goldens in
`docs/fixtures/food-daily-v4/`.

- Written only for a document holding at least one `assistant_estimate` value or one lowered tier.
  Any other document is written as version 3 or 2 exactly as before, byte for byte.
- Origin `assistant_estimate` joins the closed origin table. The value exports `state:
  "estimated"`, `calculated: false`, `source_kind` `assistant_estimate`, and `estimate_quality`,
  required, `medium` or `low` only (a `high` is rejected for this kind).
- No `content_hash`, no address, no prompt text and no reply text. Today the export writes each
  provenance's stored `source_release_id`; for this kind it writes the constant
  `assistant-pasted-reply` instead, never the per-capture identifier, so no digest of the prompt
  or reply leaves the device through the export.
- An unknown value takes its row origin from the entry's first provenance in catalogue order
  today. That lookup skips `assistant_estimate` provenance, so an unknown is never attributed to
  the assistant; decision A8 guarantees another provenance exists.
- Every `approved_estimate` value in a version 4 file carries `estimate_quality_basis`, closed
  list `catalogue` or `lowered_on_assistant_advice`, and `estimate_quality` is the tier shown for
  that log. In a version 3 file the key is absent.
- `notes` gains one constant sentence under `assistant_estimates`: "origin assistant_estimate
  marks a value estimated by the user's own assistant from a description of the food and accepted
  by the user for that entry. It is not measured and does not come from a label or a food
  composition table."
- Validator row for 4: version 3's row, with at least one `assistant_estimate` value or lowered
  tier required. It may hold any number of `approved_estimate` values, including none (version 3
  requires at least one; version 4 does not). A version 2 or 3 file carrying any of
  these fields is rejected. 2, 3 and 4 replace each other for a date under the same Drive file ID.
  A build without this change rejects a version 4 file in `validate` and so fails closed.
- An unticked or dropped suggestion exports as unknown, never zero.

## 10. Privacy and egress

No new network destination, transport or background work. Two things are new, and both need the
owner's explicit approval before any code (decision A2, given on 16 November 2026 for the wording
below): **a new clipboard payload**, and **new
content in archives and in the daily export**. This proposal does not edit
[`privacy-and-egress.md`](privacy-and-egress.md); the implementing change does, with the wording
the owner approves, and checks `privacy-policy.txt` against it. Proposed wording:

New row in "Allowed egress":

> | Clipboard, this iPhone only, expiring after ten minutes | The assistant prompt for one food on Confirm: the food's name, variety, state and details (bone, skin, drained, packing medium, fortification), including any words the user typed when correcting them, its brand unless the user switches it off, the basis, a 16-digit code derived from that description, the nutrient values already known with a plain phrase for each source, the estimated values with their quality tier and whether each is from the same or a similar food, the nutrients still unknown, and fixed instructions with the reply format. The name is sent as shown, so a brand, shop or pack-size word inside it is sent too, and the preview shows it. Never the amount eaten, a time or date, a note, a barcode, the shop or price of a purchase, receipt text, an entry, record or release identifier, a source address, health data or any other entry | Only when the user taps Copy prompt on Confirm and then Copy on the preview that shows the exact text. The app sends it nowhere and has no destination of its own; where the user pastes it is the user's choice | assistant-pasted-estimates-v1 |

New sentences under "Stays on the device unless the user sends it":

> **A pasted assistant reply** is read on the device, through the system paste control, which reads the clipboard only when tapped, and is never sent anywhere. The app contacts no assistant. The reply block the user accepted a value from is kept with that logged entry, together with the prompt it answers, and is carried by food archives the user exports or backs up; text pasted around the block is not kept. The Drive food export carries the accepted values with origin `assistant_estimate` and their tier, and whether a catalogue estimate's tier was lowered on the assistant's advice, never the prompt, the reply or a hash of either.

What the owner should weigh: once copied, the prompt is the owner's to paste, and it then reaches
whichever assistant and provider they choose, under that provider's terms, which the app cannot
see or control. That is the same position as the screenshot it replaces, with less on it: a
screenshot of Confirm also shows the amount.

## 11. Architecture gate

**Responsibilities**

| Responsibility | Home | Boundary |
|---|---|---|
| Reply schema types, the strict parser, row and reply rejection codes, the mechanical bounds | `FoodLedgerDomain` | pure; text in, result out |
| Eligibility (section 5.1), ranking position, tier ceiling and lower-only rule | `FoodLedgerDomain` | pure |
| `assistant_estimate` provenance kind, its validation, food contract 11 | `FoodLedgerDomain`, `CanonicalFoodProjection` | pure, closed versions |
| Capture and choices evidence types | `FoodLedgerDomain` | pure |
| Prompt builder and request code, from the Confirm state | `FoodLedgerApplication`, through `CanonicalEncoding` and `Digesting` | existing ports |
| Suggestion state on Confirm (paste, tick, clear, subject check), outside `FoodCorrection`, with reducer actions | `FoodLedgerApplication` | no new port |
| Save: merging ticked values, building and committing the capture, verification on save and reopen | `FoodLedgerApplication` (`FoodConfirmationService`), through `LedgerIDGenerating`, `LedgerClock`, `Digesting`, `CanonicalEncoding` | existing ports |
| Quick add ineligibility, re-log offer, re-resolution drop and notice | `FoodLedgerApplication` | existing ports |
| Export origin, version 4 shape rule | `FoodLedgerApplication` (`FoodDailyExportOrigin`, the shared shape rule) | closed table |
| Migration `v11_assistant_estimate`, store open check | the GRDB store | metadata only |
| The section, preview, rows, labels and copy for every rejection code | `FoodLedgerPresentation` | presentation only; labels come from stored provenance and evidence, never a view-only flag |
| The text paste control | one new file in `FoodLedgerPresentation`, named in the phase gate, holding a SwiftUI `PasteButton` for plain text only | `check-boundaries.sh` allows clipboard reads only in `FoodLabelPhotoUI/LabelPastePicker.swift` today; that rule is extended to exactly this second file, with a failing fixture |
| The clipboard write (local only, ten-minute expiry) | the app target, as Copy JSON does it, passed to the preview as a closure | `FoodLedgerPresentation` may not import UIKit |

**Ports.** No new protocol. The parser and prompt builder need no clock, identifier or hash of
their own beyond the injected ones named above. The one new seam is the clipboard-write closure
injected from the app target; the clipboard is read only by the paste control, on the user's
tap. `GenericRecordNutrientLookup` is not used by this route.

**Dependency direction.** Unchanged: presentation and infrastructure depend on application, which
depends on domain. No new target. No network-backed type is composed by anything this route adds,
and a boundary test says so.

**Version allocation.** Prompt `assistant-estimate-prompt-v1`; reply
`assistant-estimate-reply-v1`; parser `assistant-estimate-parser-v1`; capture
`assistant-reply-capture-v1`; choices `assistant-estimate-choices-v1`; food contract 11, migration
`v11_assistant_estimate`, `food-ledger-v11`; daily export version 4. Each is closed: a new field,
unit, tier, bound or prompt sentence is a new version, and a stored capture is always verified
with the parser version it names.

**Invariants (closed).**

- Unknown is not zero. Nothing is defaulted, converted or reinterpreted between bases.
- An assistant estimate is never measured, never above `medium`, and never replaces a label value,
  a catalogue estimate or a merged record's value. One source per nutrient.
- A reply authorises nothing. Each saved value is a row the owner ticked, saved by the one Log
  action, bound to the stored reply it came from. Nothing is ticked by default and there is no
  bulk tick.
- A tier is only ever lowered by this route, for one log.
- The catalogue, its release and the capture manifest are never changed.
- The app makes no network call here and never reads the clipboard without the user's tap.
- Existing records, archives and exports decode and re-encode unchanged; a log without assistant
  estimates keeps its contract and its bytes.
- No medical wording, target or classification.

**Extension axes.** Other Confirm routes (generic rows, Open Food Facts products), each with its
own verifier change; a reply version with new fields; record names in the prompt for similar-food
estimates, which also widens the clipboard payload and so needs an egress amendment and the
owner's approval. Each is a versioned contract change, not configuration. The eligibility rule, the
ceiling, the ranking position and the evidence binding stay closed.

**Contract tests** (synthetic fixtures only, in a new `docs/fixtures/assistant-estimates-v1/`: prompt
goldens, reply texts and a manifest of expected codes):

- Prompt: a golden per shape (with and without brand, variant, details; per 100 g and per 100 ml;
  no estimates; nothing missing); the same state gives the same bytes; none of the never-sent
  fields can appear (a state seeded with marker values for amount, note, barcode, identifiers and
  assumption text yields a prompt with no marker); the request code changes with each subject field
  and with nothing else; pasting the prompt itself gives `not_json`.
- Parser: one fixture per whole-reply code and per row code, with the precedence order pinned; a
  block inside a code fence and one with text before and after are read; a repeated JSON key
  and a bare `NaN` give `not_json`; a string number, a boolean and a null as `value`, an extra key
  at each level and a 40-row array give `keys` even beside a usable row; a negative and an
  out-of-range number give the row code `value` and leave the other rows usable; a wrong unit
  names the key's own canonical unit for a kcal, g, mg, mcg and mL key; the per 100 g bounds at and just over each limit; `exceeds_parent`
  against a known parent and against a ticked sibling, in both tick orders; a zero is accepted; an
  instruction written inside and outside the block changes nothing.
- Reviews of 16 November 2026 added: capture verification reproduces every row code from the
  stored payload alone, and altering any parse-context field fails it; a string over 40
  characters or outside the character set gives `keys`; request code goldens do not change with
  display wording, and change with fortification; a conflicting key and a bounded key give
  `not_fillable` and keep their stored value; a tier tick on a key then withheld or left out is
  not saved; the save service refuses a ticked row that is ineligible, above `medium`, above its
  parent (including after a leave-out undo on the parent) or bound to another request code,
  whatever the reducer did; an assistant value alone does not unblock Log; an entry whose first
  known value in catalogue order is an assistant estimate exports its unknowns with the
  non-assistant row origin; a version 4 file holds no capture digest (seeded marker); with choices
  evidence altered the value exports the manifest tier with basis `catalogue` and the log shows
  "Evidence not available"; a re-log or favourite with nothing ticked holds no capture or choices
  ID and its contract floor is not 11, and with one tick it cites a new capture; with several
  captures accumulated the reader picks the current one; a tick-only save on a reopened log
  reproduces the saved outcome for a selected, a rejected and an estimate entry; the GRDB and
  in-memory stores pass the same tests for both evidence kinds; `assistant_estimate` is rejected
  as a conflict candidate; an encoded `FoodConfirmationState` holds no suggestion state; a
  failing boundary fixture for a paste control outside the two allowed files.
- Eligibility and ranking: a label value, an Open Food Facts value, a merged record's value and a
  catalogue estimate (kept, withheld, left out) each refuse a value row with the right code; a
  bounded value refuses; an unknown key with no catalogue estimate accepts.
- Ceiling: `high` on a value is refused by the parser, by `NutrientEntry` validation and by the
  export validator; `.measured` and `.bounded` reject `assistant_estimate`; each required
  provenance field is rejected when missing.
- Tiers: a lower tier ticks, shows and exports, on save and on reopen; with the choices evidence
  altered, or naming a tier that is not lower, the manifest's tier is shown; equal and higher are not offered; a tier row for a key
  with no kept estimate is refused; a lowered tier changes no value, provenance byte or manifest
  byte.
- Confirm: nothing is ticked after a paste; there is no bulk tick; Log with nothing ticked stores
  no capture; a second paste clears ticks after the question; a correction of details clears ticks
  and blocks the rows, and returning to the subject leaves them unticked; a basis change clears
  them; a change of amount or a leave-out does not; a withheld catalogue estimate that returns
  after a correction is unaffected and no assistant value sits on its key.
- Save and reopen: each row of the table in section 6.4; a tick alone on a reopened log writes a
  new resolution version, keeps identity, decision record and outcome, and is not a correction;
  untouched nutrients keep their provenance bytes; a save failure leaves neither capture nor log;
  the capture is found through provenance and, with no assistant value left, through the
  decision's evidence IDs, also after an archive restore.
- Evidence: altered capture or choices evidence shows "Evidence not available" and changes no
  stored value; a stored block that no longer parses to the stored rows fails verification; a
  missing row fails closed; the pasted-label, label-estimate, web-proposal, estimate-manifest and
  leave-out readers ignore both new kinds, and their reader ignores each of theirs.
- Other routes: re-resolution stores no assistant value, shows its notice and leaves the saved
  version unchanged; quick add and re-log of an entry holding an assistant value, or citing a
  capture with none ticked, open Confirm; a one-step save of a state holding a capture is refused;
  the earlier reply is offered unticked when the code matches and not offered when it does not;
  search results and evaluation counts are identical with and without assistant estimates.
- Versions: the floor returns 11 for each of the three markers, including one found only in a
  candidate decision; a contract 10 reader declines it; contract 1 to 10 fixtures re-encode byte
  for byte; the migration is metadata only.
- Export: each bullet of section 9 through serialisation, Drive validation, reconciliation and
  recovery; a day whose only assistant value was unticked is written as version 3 or 2.
- Boundary: nothing added composes a network-backed type (with a failing fixture).
- Simulator journey: open Confirm for a synthetic entry, copy the prompt, paste a synthetic reply,
  read a rejection, paste a good reply, tick one row, log, reopen, read the details.

Validation is the gates in `AGENTS.md`. The search evaluations are not required by this route's
own change, since its values never reach search; the phase gate confirms that with the
identical-results test above.

## 12. Decisions for the owner

All eight were decided by the owner on 16 November 2026, each as recommended. The owner then
accepted the contract as a whole on the same day (section 14). A8 was added by
the invariant review.

- **A1. May the brand be in the prompt? Decided by the owner on 16 November 2026: yes, shown in
  the preview, with an "Include brand" switch that starts on** (the recommendation). A brand lets the assistant look at the maker's own
  figures, which is most of the value for a packaged food, and the owner already shows the brand
  when they screenshot a pack. Cost: the brand reaches whichever assistant the owner pastes into.
  Alternatives: switch starts off; brand never included (weaker estimates for branded foods, and
  the name may still hold a brand word).
- **A2. The clipboard payload and the stored reply (section 10). Approved by the owner on 16
  November 2026, as worded in section 10 at 676159f, with the clipboard limited to this iPhone
  and expiring after ten minutes** (the recommendation). The approval covers that wording and
  nothing wider: a further field, destination or trigger needs a fresh approval. If a later
  decision narrows the feature (A4 without tier lowering, say), the sentence about a lowered tier
  is dropped and no new approval is needed. `privacy-and-egress.md` is still edited only by the
  implementing change.
  Alternative: let the prompt use the shared clipboard so it can be pasted on a Mac; more
  convenient, and it widens where the text can travel.
- **A3. Which routes get it? Decided by the owner on 16 November 2026: Your food database
  entries only in v1** (the recommendation). It is where
  the gaps are, and it leaves the label and web verifiers untouched. Alternative: every Confirm
  route, which changes those verifiers and their admission rules and is a larger phase.
- **A4. What does a tier suggestion do? Decided by the owner on 16 November 2026: a ticked
  suggestion lowers the tier shown for that log only, and never raises one** (the
  recommendation, taken with the cost below stated). So sections 5.3, 6.3 and the
  `estimate_quality_basis` field of section 9 stand, and acceptance of the proposal adds the dated
  amendment note to estimates v2 sections 3.3 and 5. Alternatives: show it as advice with nothing to tick
  and nothing stored (smaller: no choices evidence and no `estimate_quality_basis` in the export);
  or leave tier suggestions out of v1. The architecture gate's view, stated for the owner: tier
  lowering is the costliest part of this route (a second evidence kind, an amendment to estimates
  v2, a precedence rule and a new export field) for a change to one log's display, and leaving it
  out removes most of the amendment surface.
- **A5. A catalogue estimate that is withheld or left out. Decided by the owner on 16 November
  2026: the reply cannot fill that nutrient** (the recommendation). It keeps "one source per nutrient" fixed for the log and means a returning
  catalogue estimate never meets an assistant value. Alternative: let a reply fill a withheld key
  (more coverage where a record contradicts the details), at the price of a rule for which one
  wins when the contradiction is later removed.
- **A6. Re-log and quick add. Decided by the owner on 16 November 2026: the earlier reply is
  offered again, every row unticked, when the details match** (the recommendation). Alternatives: never carried, so each new log needs a fresh
  paste; or carried already ticked, which is not recommended because it selects by default. A
  value wanted on every log belongs in the catalogue.
- **A7. A suggested zero. Decided by the owner on 16 November 2026: accepted, as a labelled
  estimate the owner ticks, written out in words ("none: 0 g")** (the recommendation).
  Alternative: refuse every zero from a reply, which is stricter about "unknown is never zero" and
  loses true zeros such as fibre in butter.

- **A8. May an assistant value be a log's only known nutrient? Decided by the owner on 16
  November 2026: no** (the recommendation). When every
  other value was withheld or left out, Log stays blocked. It keeps a model's reply from ever
  being the whole of a log's nutrition and keeps every exported unknown attributable to a real
  source. Alternative: yes, which fills a little more and needs an export rule for an entry
  whose only provenance is the assistant.

## 13. Left to the phase gate

Both reviews of 16 November 2026 left these to the implementation phase's own gate. None changes
the contract's rules; each must be settled against the code before production work.

- A tick-only save on a reopened log writes a new product version and a new resolution at ordinal
  1 under today's save path, so quick add's detector would read it as corrected; the new
  ineligibility case is tested ahead of the sheet case, and the assertion text must not start with
  the corrected-confirmation wording. List the sites.
- `CandidateDecision.init` recomputes the outcome from contradictions, so the saved outcome is
  reproduced and asserted equal, not copied.
- The new `sourceID` reaches generic consumers (Food Log row source lists, views that fall back
  to the raw identifier): enumerate them and give the display name.
- Repeated keys and a bare `NaN` are not detectable with Foundation's JSON readers, so the parser
  needs its own strict reader; "same state, same bytes" needs a pinned number format in the prompt.
- View reply escapes control and bidirectional characters, although section 4.1's limits leave
  little room for them.
- Whether Your food database candidates can carry `missing_conversion`, and the database
  candidate's release `sourceID`, were not confirmed in code; section 5.1's wording covers both.

## 14. Review record

- 16 November 2026: written in one session. Read in full for it: `AGENTS.md`, estimates v2,
  estimates v1, `privacy-and-egress.md` and daily export v2. Read in part: the Confirm save path
  (`FoodConfirmation.swift`, the types at the top and `save` through `relogState`), and
  [pasted label AI text v1](pasted-label-ai-text-v1.md) sections 4.4 to 4.9 with its outline only.
- **Not read by the author:** `FoodReresolutionService`, the quick add service, `FoodDailyExport`
  beyond its origin table, `SourceRelease` and `CaptureEvidence` validation, `FoodDetailsSheet`
  and `privacy-policy.txt`. The reviewers below read the first four; `FoodDetailsSheet` in part;
  nobody has read `privacy-policy.txt`, `DailyFoodExportIdentityPolicy` or the re-resolution
  providers for this text.
- 16 November 2026: one local Qodo pass on 46f1b8d (auto depth, issue and compliance reviewers,
  coverage complete), four findings, all accepted and folded in: the version 4 validator line read
  as forbidding catalogue estimates; a wrong JSON type had both a whole-reply and a row outcome;
  rejection and zero copy named mg for every nutrient; and a lowered tier had two authorities
  against estimates v2, now stated as an amendment with a precedence rule.
- 16 November 2026: blind architecture-gate and invariant reviews by two subagents on 0113764,
  each checking the claims against the code the author had not read. Both PASS WITH CHANGES, six
  blocking findings each, overlapping. Neither found a route from an assistant value to a measured
  value, to a tier above `medium`, to a default selection or to a save without a tick and Log; the
  save path, re-resolution, quick add, port and stored-shape claims were confirmed in code. Folded
  in, each checked first: a conflict between label values is stored as `.unknown` and was
  eligible (now `not_fillable`); the per-reply release identifier would have reached the Drive
  export (now a constant); strings in the block were unbounded (now limited); fortification was
  missing from the details and the request code; a tier tick could outlive its estimate; the
  egress row was incomplete; verification could not reproduce context-dependent row codes (now a
  stored parse context, with the sibling rule a tick rule and save as the authority); unknowns
  could be attributed to the assistant in the export (row origin skips it, and decision A8); the
  paste control and clipboard write had no legal home under the boundary script; re-log carried
  capture IDs by default; the request code hashed display words; the whole-paste hash is gone.
  Section 13 lists what they left to the phase gate. **These fixes have had no review of their
  own.**
- 16 November 2026: the owner decided A1 (brand included, switch starts on). A2 to A8 are open,
  and the proposal as a whole is not accepted.
- 16 November 2026: the owner approved A2, the egress wording of section 10, with the clipboard
  on this iPhone only. A3 to A8 are open, and the proposal as a whole is not accepted.
- 16 November 2026: the owner decided A3 (Your food database entries only in v1). A4 to A8 are
  open, and the proposal as a whole is not accepted.
- 16 November 2026: the owner decided A4 (a ticked tier suggestion lowers the tier for that log
  only), with the architecture review's cost put to them. A5 to A8 are open, and the proposal as a
  whole is not accepted.
- 16 November 2026: the owner decided A5 (a reply cannot fill a nutrient whose catalogue estimate
  is withheld or left out). A6 to A8 are open, and the proposal as a whole is not accepted.
- 16 November 2026: the owner decided A6 (on re-log and quick add the earlier reply is offered
  again, unticked). A7 and A8 are open, and the proposal as a whole is not accepted.
- 16 November 2026: the owner decided A7 (a suggested zero is accepted and shown in words). A8 is
  open, and the proposal as a whole is not accepted.
- 16 November 2026: the owner decided A8 (an assistant value is never a log's only known
  nutrient). All eight decisions are taken, each as recommended. **The proposal as a whole is not
  accepted**, and the fixes folded in after the blind reviews have still had no review of their
  own.
- 16 November 2026: **the owner accepted the contract.** A repeat review of the revision made after
  the blind reviews was recommended first and not taken, so those fixes had no review of their own
  at acceptance; the items the reviewers left to the phase gate are in section 13. Recorded with
  the acceptance: dated amendment notes in estimates v2 and daily export v2.
- 16 November 2026, before the merge the owner asked for: Qodo's review of the PR head was a
  skipped run (no findings, review not complete), so one more local Qodo pass was run on the whole
  branch at 4ce8a6f (coverage complete). One new finding, fixed: the parse context did not hold a
  kept catalogue estimate's value for a parent nutrient, so a child above it would have been
  offered and then refused at Log. The four findings of the first pass were reported again by ID
  and are the ones already fixed.
