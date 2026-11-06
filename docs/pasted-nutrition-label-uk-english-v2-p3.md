# Pasted nutrition label, UK English v2: P3 freeze and fresh-set protocol (#371)

Status: **revision 3, 6 November 2026.** The architecture gate passed revision 1 with nine changes, all applied (section 8). The re-gate of revision 2 passed with the R2 dash cases added in this revision, and the invariant review's finding (R3 limited to amount columns) is applied with its negative test. This is phase P3 of [the UK reader v2 plan](pasted-nutrition-label-uk-english-v2.md), after [P2](pasted-nutrition-label-uk-english-v2-p1.md) (merged in PR 413). It lands in one commit before any v2 fresh label is collected. It changes only test code (the harness, the scorer and the freeze) and this protocol. **No product source file changes**, so no shipped behaviour changes, no reader v3 pin moves and no UK reading rule changes.

[The v1 P3 spec](pasted-nutrition-label-uk-english-v1-p3.md) is the base. Everything it says applies to v2 unless a section below replaces it.

## 1. The freeze (re-pin 2 of `UKReaderFreezeTests`)

Frozen as of the P3 commit, which is the reference of the v2 P4 release check:
- parser `nutrition-label-text-parser-uk-v3`;
- identity `pasted-label-identity-v3`;
- the reading policy `.ukDevelopment` (both formats, identity v3);
- the UK reader adapter, with its set-aside list;
- the UK harness;
- scorer `uk-fresh-scorer-v2` (section 2).

Any later change to what one of them does is a new version and needs a new fresh set.

P2 moved the pins to uk-v3 (re-pin 1). This commit is re-pin 2:
- **Pin 1, version strings:** unchanged.
- **Pin 2, rule tables:** unchanged. The listing and its hash are byte-identical.
- **Pin 3, source files:** re-hashes `UKFreshSetProtocol.swift` (sections 2 and 3) and `UKDevelopmentSet.swift` (its set-aside type moves to the release harness), and nothing else.
- **Pin 4, new:** a SHA-256 of a listing of the scorer version and R1 to R3's closed tables (the percent unit, the energy partner pair, the dash markers, the label unit tokens).

**Files in the commit:**
- the two pinned harness files;
- `UKReaderFreezeTests.swift` (re-pin 2 and pin 4);
- `UKFreshSetScorerTests.swift` and the new `UKFreshSetScorerV2Tests.swift` (unpinned tests);
- this spec, `docs/README.md`, the plan's status line, `.github/scripts/ci_changes.py` (this spec is cited by code) and the ledger.

## 2. Scorer v2: three closed matching rules

The P2 development re-run flagged 22 values on the v1 fresh set as wrong where the reading was right (P1 spec amendment 1). Left alone, the scorer would stop the v2 check on those same shapes. Judging each flag by hand after the run would put a post-hoc exception into a sealed bar. So the scorer gains three closed rules before collection.

Like v1 P3 section 3, **each rule only decides which printed cell a read value is compared with.** The comparison itself (comparator, exact number, canonical unit, column basis) is unchanged, and a match never counts as reading a ledger nutrient. Any value still flagged is wrong. A per-value audit may be reported, but it never changes the outcome. A flag believed to be an artefact needs a scorer amendment and a new fresh set.

- **R1, the percent column among reference columns.** A reader header with basis `reference_intake` normally matches the one transcription column with that basis. When the transcription has two or more such columns (a `%RI` column and a reference amount column, which S4 sets aside), it matches the one column whose values, apart from dash or `Trace` markers, are all percentages, with at least one. If there is no such column, or more than one, the match is ambiguous (wrong).
- **R2, the energy percentage printed once.** The energy reference intake percentage is one quantity, the same whether it is stated against kJ or kcal. A label prints it once, on one energy line. The rule applies to a read `energy_kj` or `energy_kcal` cell in a reference intake percent column (R1's test) when:
  - its own transcription row has no value there, or a dash;
  - the partner energy row holds a percentage there;
  - the reader bound no partner-energy cell in that column.

  The cell is then compared with the partner row's percentage. `Trace` on the own row is a value, so the rule does not apply.
- **R3, a unit printed only in the row label.** In an amount column (never a reference intake column), when a transcribed value's unit is empty (validation requires `outside_table` for that), and the transcribed row label names exactly one canonical unit, that unit is the expected unit. "Names" means a bracket group holding a unit of the scorer's table, or a bare last token `kJ` or `kcal`. A label naming no unit, or two, gives no unit, and the value stays wrong.

**Negative cases, each still wrong (contract tests 3 to 5):**
- **R1:**
  - the reader's reference cell holds an amount;
  - two percent-only columns;
  - no percent-only column;
  - percentages against a single amount reference column.
- **R2:**
  - the partner holds a different percentage;
  - both rows hold a value (the own row is compared);
  - `Trace` or `Tr` on the own row;
  - a dash on the own row with a different percentage, no percentage or a dash on the partner row;
  - a dash on the own row with the reader binding both energy cells (the own cell is compared with the dash);
  - a non-energy row;
  - an amount column;
  - the same percentage bound to both energy rows (one of the two is wrong).
- **R3:**
  - a read unit other than the named one;
  - a label naming two units;
  - a label naming none;
  - a printed unit that the label contradicts (the printed unit is never overridden);
  - a reference intake column: R3 applies only in amount columns, because a bare number under a `%RI` heading is a percentage, so a read amount carrying the row label's unit there stays wrong;
  - a different number.

Disabling any one rule fails its own tests.

**Development re-run (counts only), scorer v2 on unchanged P2 run outputs:**

| Set | Reached Confirm | Values checked | Wrong, scorer v1 | Wrong, scorer v2 |
|---|---:|---:|---:|---:|
| P1 development set (24) | 17 | 201 | 0 | 0 |
| v1 fresh set, development data (24) | 13 | 228 | 22 | 0 |

All 22 were decided by a rule: R1 decides 19, R2 decides 4 (3 of them also through R1) and R3 decides 2. One of R2's 4 is the dash case: the page prints the energy percentage on the kJ line and a dash on the kcal line, and parser v3 binds it to kcal.

R2's dash case was added after the gate. The gate's R2 required the own row to be empty, and this real shape remained flagged under that wording. The re-gate checks this widening.

## 3. Harness change: set-aside files in the release run

For each label it reads, `UKFreshSet.runAll` also writes `set-aside/<id>.json`, with schema `uk-set-aside-v1` (`schema`, `label_id`, `entries`). This is the same file the development harness writes from P2. It is written before the label's run output and its `wrote <id>` line, so every `wrote` ID has its file and a rerun writes none for labels it does not read. A failed set-aside write leaves no run output, so the one permitted rerun reads that label again rather than refusing an output the log does not account for.

The run schema `uk-english-v1-fresh-run-v1` and the transcription schema `uk-english-v1-fresh-transcription-v1` are unchanged and keep their names: they name formats, not sets (gate Q3). A v2 run is identified by its folder, by the commit in the run log's start line and by the scorer version.

`UKFreshSet.SetAsideFile` replaces `UKDevelopmentSet.SetAsideFile`, so both harnesses write one type. The file is for audit and for P5's Developer tools; the scorer does not read it.

The file is built from the same text by the same reader. A test holds that each S2 entry holding a value is one of the reading's `uk_set_aside` unread rows, in order.

**Clean checkout.** The `run` step refuses a checkout with local changes, untracked files included (12.2.7 item 1). The run happens from a clean checkout or worktree at the P3 commit, or at a descendant that changes no pinned file.

## 4. The v2 fresh-set protocol

As v1 P3 section 4, with these changes.

### 4.1 Private folder

The folder is `~/WHR-label-eval-private/uk-english-v2/fresh`, outside every git checkout. It is new. Nothing from the v1 fresh folder is copied into it except the exclusion records.

### 4.2 Exclusions (replaces 4.1)

- **The P1 development set**, as v1: every site and product that v1 P3 section 4.1 lists.
- **The v1 fresh set's products.** Every v1 fresh product, and each of its texts' SHA-256, is excluded. Its sites stay eligible, in tier B (section 4.3).
- **The private exclusion list** gains the v1 fresh products and text hashes, written to the v2 folder from the v1 fresh records before collection starts. A collected text whose SHA-256 matches either development set is skipped `development_set`.

### 4.3 Tiers and retailer rotation (replaces the retailer list of 4.3)

Owner decision, 6 November 2026: sites new to both development sets come first.

1. **Tier A retailers, new sites,** rotated as 12.2.3: 1. Co-op, 2. Lidl GB, 3. Planet Organic, 4. Sous Chef, 5. Booths, 6. Farmfoods, 7. Boots.
2. **Tier B retailers, the v1 fresh set's sites,** rotated the same way: 8. Tesco, 9. Sainsbury's, 10. Asda, 11. Morrisons, 12. Waitrose, 13. Ocado, 14. Iceland, 15. Holland & Barrett, 16. One Stop.

A retailer slot tries tier A in rotation. It moves to tier B only when every tier A retailer is exhausted, blocked or capped for that slot's category. The 50-result window, the cap of 3 labels per site and the `blocked` rule are unchanged.

**A label's tier is its site's tier, whatever the slot kind.** That covers manufacturer and PDF slots, `kind_fallback` fills and walk-again fills: a label from any v1 fresh site is tier B, and every other label is tier A. Tier is assigned from the site and slot before a page is opened, and recorded in the skip log and in `source.json`. It never depends on what a label shows.

Manufacturer and PDF slots, the Google procedure and the fallbacks are unchanged.

### 4.4 Collectors and copy method (Amendment 2 from the start)

Owner decision 5 of the v2 plan: keep the scripted copy.
- **Web pages:** an agent in the built-in browser copies by scripted selection, exactly as v1 Amendment 2 item 1. The agent runs in its own session, which has never read the parser source, this repository's tests, or either development set's per-label results or set-aside files.
- **PDFs:** copied in Preview with the system copy command, as Amendment 2 item 2. Each candidate is listed to the owner first.
- **Blocked sites:** a site that shows the agent a CAPTCHA, bot check or traffic-verification page is logged `blocked` and never bypassed. The owner in Safari becomes its collector, as Amendment 1 item 1.
- **`collectors.json`** in the v2 folder fixes every site's starting collector before collection. A site that blocked the agent in v1 starts with the owner in Safari. Every other site starts with the agent. Every switch is recorded.
- **The blind transcriber** has never seen either development set's per-label results or set-aside files.

The copy check (v2 plan section 3) found that scripted copies add blank lines and a title line that Safari copies do not. Every rate is reported beside its copy-method counts, with that caveat.

### 4.5 Roles, seals, run, bar and reporting

As v1 P3 sections 4.4 and 4.5 and reader v3 12.2:
- blind transcription;
- owner verification with two seals;
- one run, with one rerun only for an infrastructure failure;
- scored by scorer v2.

**The bar is unchanged: zero wrong values** in every table that reaches Confirm, harness and device step alike. The decline-rate goal (at most 25%) and the correction burden (median at most 1) are reported, never gating.

**By tier.** Every rate and rule-of-three limit is reported:
- for all labels;
- for tier A on its own, the figure least dependent on the sites the rules were built on;
- for tier B.

No tier rate is given below 5 labels; only its counts are shown. The bar applies to all labels together.

**Set-aside counts** are reported by rule only.

### 4.6 The device step and P5

The device step reads under `.ukDevelopment`, switched on by the `#if DEBUG` device switch. It is scored with the same transcriptions and scorer v2, with no separate judgement.

v1 P3 section 6's open owner decision before P5 now reads for v3. The recommendation is that `.product` becomes equal to `.ukDevelopment` (both formats, identity v3), so the check measures what ships, with a versioned identity contract for manifests naming identity v3. The whole-reading Taiwan check of v1 P3 section 6 is unchanged.

## 5. Invariants

- No product source file changes; the reader v3 freeze, its pins and every Taiwan reading are unchanged.
- Pins 1 and 2 are unchanged; pin 3 changes only for the two harness files; pin 4 is new.
- The UK harness never builds a UK manifest.
- Each scorer v2 rule only chooses the printed cell compared; it never changes a comparison or forgives a flagged value.
- No real label text, value, product name, address or hash enters the repository. Set-aside files hold printed text, so they live only in the private folder. Results report counts only.

## 6. Contract tests

1. **Freeze:** `UKReaderFreezeTests` passes with re-pin 2 recorded. Pins 1 and 2 are unchanged, pin 4 holds the scorer version and the R1 to R3 tables, and pin 3 is re-hashed for the two harness files only.
2. **Positive:** a synthetic table with a `%RI` column, a reference amount column and the energy percentage printed once scores with no wrong value. So does an energy row whose unit is printed only in the label.
3. **R1 negatives**, as section 2.
4. **R2 negatives**, as section 2, and a dash on the own row is not a value, for every dash in the pinned list.
5. **R3 negatives**, as section 2, and `labelUnit` names one unit or none.
6. **Residual:** every v1 P3 test 6 negative passes unchanged. Disabling any rule fails its tests (checked once by mutation, not committed).
7. **Set-aside:**
   - the release run writes one file per `wrote` ID, with none after a rerun that reads nothing;
   - the file has keys `schema`, `label_id` and `entries`, and round-trips unchanged;
   - each S2 entry holding a value is one `uk_set_aside` unread row of the reading.
8. **Unchanged steps:** the v1 P3 seal, refusal and run tests pass unedited.
9. **Development evidence** (opt-in, counts only): section 2's table.

## 7. Gate questions, answered

- **Q1.** Scorer unchanged with an owner-judged artefact exception, or fixed before collection? **Fixed before collection** (section 2). An exception judged after the results are seen weakens the bar.
- **Q2.** Is tier B compatible with independence? **Yes.** Tier is fixed by site before a page is opened, both development sets' products are excluded, tier A is reported on its own, and the bar applies to all labels (section 4.3).
- **Q3.** Rename the schemas? **No.** They name formats; renaming would move pins 1 and 2 for no gain (section 3).

## 8. Gate findings map (revision 1)

1. The owner-judged artefact exception is replaced by scorer v2 R1 to R3, the residual rule and pin 4: sections 1 and 2.
2. Tests for each rule, the negatives and the development re-run: sections 2 and 6.
3. The stale harness comment ("identity v2") and the displaced `builder` comment are fixed before re-hashing, and every file in the commit is listed: section 1.
4. `wrote` and set-aside correspondence, and S2 entries against the unread rows: sections 3 and 6.
5. Tier is defined for every slot kind and fill, and fixed before a page is opened: section 4.3.
6. `collectors.json` is fixed before collection, and the blind transcriber's isolation is stated: section 4.4.
7. The P5 decision is restated for identity v3, and the device step is scored the same way: section 4.6.
8. Set-aside files stay private, and are reported by rule only: sections 4.5 and 5.
9. No tier rate below 5 labels: section 4.5.
