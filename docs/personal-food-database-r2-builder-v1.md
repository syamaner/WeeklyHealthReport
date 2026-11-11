# Personal food database: R2 builder and estimate companion v1

Status: **draft, 10 November 2026, phase R2a of #424. Tooling only; synthetic data only.** It
implements the R2 rules already decided in the [E3 disposition](personal-food-database-e3-disposition.md)
(sections 4 and 5) and the [estimates contract](personal-food-catalogue-estimates-v1.md) (sections 2,
3 and 6), under plan revision 7, decision 11. It moves no bar and changes no frozen tool, seal,
freeze record or frozen hash, and the app's importer is a separate phase.

R2 is R1 plus owner-approved estimates, in the schema `personal-food-catalogue-estimates-v1`. Its aim
(decision 11) is a labelled best estimate for every entry; unknown stays unknown only where no
admissible source exists. R2 can be rebuilt as estimates are added: every build is a new release
with its own ID and its own output folder. The companion is cumulative: each round holds the whole
approved set, not only the new estimates.

## 1. Who does what

| Step | Who | Reads private data |
|---|---|---|
| This tool, its format and synthetic tests | this session | no |
| Convert the private estimate companion into `pfd-estimate-companion-v1` | evaluator | yes |
| Run `build-r2`, report counts and the R2 ID | evaluator | yes |
| Draft estimates for entries still without nutrition; approve each one | owner, with the food agent | yes |

This session never reads the companion, the R1 file or the build output, only the printed counts.

## 2. Input: `pfd-estimate-companion-v1`

One JSON object, UTF-8 without a byte-order mark, no repeated keys, written canonically (sorted keys,
no spaces, one trailing newline):

```
{"schema": "pfd-estimate-companion-v1", "r1_release_id": "pfc:sha256:<64 hex>", "estimates": [...]}
```

`estimates` is sorted by (`entry_id`, `nutrient`), each pair at most once. Each estimate has exactly:

| Field | Meaning |
|---|---|
| `entry_id`, `nutrient` | an R1 entry and a key of the nutrient inventory |
| `value`, `unit` | finite, non-negative, not a boolean; the key's canonical unit |
| `basis` | the basis the value is on; a value on another basis than the entry's is withheld (rule 8) |
| `evidence` | the contract section 2.2 record without `id`, `entry_id` and `nutrient` |
| `underlying_source` | closed: `not_applicable` (national composition or a manufacturer page), `stated_independent`, `open_food_facts`, `not_stated` (aggregators only) |
| `origin` | closed: `direct`, `prior_release_resolved`, `prior_release_unresolved`, `recipe_estimate` |

Every estimate in the companion is one the owner approved (`evidence.approved_as_estimate` is
`true`). A structurally invalid companion is refused whole, with no output; so is a page URL that is
not a public HTTPS address (an IP literal in any spelling, including forms such as `127.0.0.01` or `127.1` whose last label is numeric, `localhost` or a name without a dot), and a national
composition estimate naming a corpus R1 does not declare.

## 3. What `build-r2` does

Inputs: the pinned release, the R1 file and R1 build record in the private folder, the R1 unresolved
list and exclusion list the build record hashes, and the companion. It refuses unless the pinned
release has the ID in `freeze-v1.json`, the R1 file has the ID in its build record, the companion
names that R1 ID, the two lists match the hashes in the build record, and re-deriving R1 from the
pinned release, those lists and the recorded switches gives exactly the R1 bytes (so a substituted
R1 with a self-consistent record is refused).

Each estimate is then admitted or withheld, in this order (first rule wins, each withheld estimate
counted under one reason):

1. `label_kept`: R1 still has a label value for that key. The label value stays and the estimate is
   not added (disposition section 4, the 392 overlaps).
2. `recipe_estimate` and `prior_release_unresolved`: contract section 3.2.
3. `open_food_facts_source`: an aggregator value whose stated underlying source is Open Food Facts,
   or any page on an Open Food Facts host (contract section 3.1; disposition section 4.1).
4. `e3_withheld_value`: a value resolved from the prior (pinned) release (`prior_release_resolved`)
   on an entry E3 withheld, on a key E3 withheld or left unresolved, or on a key whose pinned label
   value R1 removed (including Open Food Facts values dropped by A1). Such a value may be the
   withheld value itself, so it never comes back through this route (disposition section 4.1).
5. `e3_withheld_source`: a national composition value naming the record of a generic reference the
   pinned release had for that entry and R1 removed (no laundering, disposition section 4.1). The
   rule is per entry: the same record on another entry is a judgement about that food, not a
   withheld value.
6. `own_reference`: a national composition value naming the entry's own R1 generic reference,
   whatever its role (contract section 2.3).
7. `transform`: a `derived` value whose transform is outside the closed list of contract section 6,
   applies to another nutrient or unit, or does not reproduce the value within 0.5 per cent. Each
   transform keeps its import v1 section 4 scope, so `mass-g-to-mg` applies to sodium only; the
   table is built from the v1 checker's own, so the two cannot drift.
8. `basis`: the value's basis is not the entry's.

An estimate from an independent source on a key or entry E3 withheld, or on a key A1 dropped, is
admissible (disposition section 4.1: "the evidence, not the number, decides"); these are counted, not
refused. What the tool can check mechanically, it withholds: an Open Food Facts source, a generic
record R1 removed and a prior-release value on a withheld key or entry. Whether a `direct` estimate's
page or record is the very source E3 withheld cannot be checked here, because the exclusion and
unresolved lists name entries and keys, not sources; the companion author must never write one
(contract section 3.1, a builder rule with an evaluator count), and the admitted counts on withheld
entries and keys make every such case visible for review.

Everything else is admitted. The evidence `id` is `pfe:` and the first 16 hex digits of
SHA-256 of `pfe-v1|<entry_id>|<nutrient>`, so a rebuild gives the same IDs. R2 is R1 with `schema`
set to `personal-food-catalogue-estimates-v1`, `estimated_nutrients` added to every entry (possibly
`{}`) and `estimate_evidence` (sorted by `id`) added at the top.

The tool then proves, before writing anything:

- **additive:** every entry outside `estimated_nutrients` and the top level outside `schema` and
  `estimate_evidence` equal R1 in canonical form; zero differences (disposition section 5, point 2);
- **admitted:** R2's estimates and evidence are exactly the companion rows the rules admit, with the
  same values, units and evidence, and no withheld row appears;
- **contract:** the bytes pass this repository's Python mirror of the estimates contract's file
  rules (sections 2.1 to 2.3, and section 6 arithmetic), which also runs the unchanged v1 rules on
  the v1 part. The bundled-corpus value check (section 4.3) stays an importer check; the tool counts
  national composition values but does not compare them with the corpus.

All three proofs run on the bytes about to be written. A failure prints the rule codes only, never an
ID. The tool writes the R2 file and a build record (`pfd-r2-build-v1`: pinned, R1 and R2 IDs, the
companion's SHA-256 and the R1 build record's SHA-256) to `r2/<first 16 hex digits of the R2 ID>/`
in the private folder (with the first 16 hex digits of the companion's SHA-256 appended, so a
companion that changes only withheld rows still gets its own record and counts), never overwriting a
different file, so every round's release stays available
for a later Part B binding. It prints counts and the R1 and R2 IDs only.

## 4. Counts printed (no titles, entry IDs or values)

Admitted estimates in total, by `source_type`, by inventory group (macro, micro, other) and by
`method`; withheld by reason; companion rows with an Open Food Facts source, whatever rule withheld
them; zeros admitted by `source_type`; aggregator values admitted with `not_stated`; admitted
`indexed_copy` values; the size of the admitted union of aggregator and indexed-copy values;
admitted estimates on entries E3 withheld, on keys E3 listed and on keys A1 dropped; entries with at
least one estimate; `entries_with_no_nutrition` (no label value, no estimate and no reference, R1's
own definition, so the two compare directly); and `entries_without_values` (no label value, no
estimate and no merge reference). That last count is the worklist for the next round of estimates.

## 5. Architecture gate

- **Responsibilities.** `r2/estimates_v1.py` is the pure file checker. `r2/r2_export.py` is pure:
  companion parsing, the admission rules, assembly and the additive proof. `r2/pfd_r2.py` is the only
  file that touches files, reusing the evaluator's private-path rules and `workspace_guard`.
- **Dependency direction.** The pure modules import only the v1 checker (`export_v1`) and the
  standard library. They use four of its private helpers (`_num`, `_date`, `_Reject`,
  `_no_duplicate_keys`) and its transform table, so a change there is a change here; `export_v1` is a
  skill script outside the freeze records, and the tests pin the shared transform table. Nothing imports the R2 modules except the command and the tests. Frozen tools
  are imported, never edited.
- **Invariants.** An estimate stays an estimate; one source per nutrient; unknown is never zero; no
  Open Food Facts source; no laundering of a value E3 withheld; R1's bytes stay R1's outside the
  estimate fields; output is private and counts-only.
- **Extension axes.** A new source type, transform or origin is a new companion or contract version,
  not a code switch.
- **Contract tests (synthetic).** Each admission rule and its count, including laundering through a
  withheld entry's, an exclusion's or an unresolved value's reference and through prior-release
  values; the transform scope and tolerance; every estimates-file rejection rule; each schema refusing
  the other; the additive and admitted proofs catching a change; canonical, deterministic output;
  rebuilds in separate folders; refusals for a wrong pinned release, R1 or list, a linked input or
  output, an existing different output and a root readable by others. When the estimates contract's
  shared rejection fixtures (`docs/fixtures/personal-food-database-estimates-v1/`) land with the
  importer, `estimates_v1.check_bytes` must consume them too.
