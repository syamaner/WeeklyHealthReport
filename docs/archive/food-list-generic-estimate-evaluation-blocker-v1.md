# Pasted-list generic estimate blocker

The new linked list evaluation exposes a production handoff mismatch. With a pasted
`100g raw apples` line, `FoodListImportService` retrieves the selected public generic
record and transfers 100 g into an undecided confirmation. After ordinary explicit
acceptance, `FoodConfirmationService.save` throws `unexplainedMaterialDifferences`
for the source's unknown descriptive identity fields. No entry is written.

The manual line evidence is created by `FoodListImportService.search`. CoFID retains
that supplied capture rather than making generic-search evidence. The versioned
`FoodConfirmationPolicy.isGenericEstimate` requires selected-candidate evidence of
kind `genericSearch`, as well as exclusively matching generic source provenance.
Consequently list-based confirmations do not qualify for the existing generic estimate
rule. The same target saves through the separate typed generic-search route. Original
text and quantity handoff work; the tested failure is at identity admission.

The evaluation freezes seven synthetic lists/fourteen lines with explicit per-line
record selection and acceptance, expected counts and all 39 source-backed totals.
The first trial parsed all fourteen lines correctly but saved none of the nine
supported entries. Missing and count amounts also stopped at the earlier identity
gate, so that trial does not prove quantity-specific blocking. The report keeps
supported refusal and incomplete outcomes separate from safe non-admission.

Architecture gate for a subsequent repair: preserve the manual capture, its reviewed
input method, original descriptor and line number. Connect the actual generic search
to retained generic-search evidence alongside the manual capture, using injected
identifiers and existing source/evidence contracts at the application boundary.
The source adapter must retain both links for the selected record. Do not relabel
reviewed manual speech as raw speech, invent identity values, auto-accept a result,
or broadly admit arbitrary manual/exact-product evidence as generic estimates.
Any alternative policy change requires a new explicit version and behavioural contract.

Required validation for that repair: ordinary generic list entries reach a saved
estimate after explicit acceptance; preacceptance remains blocked; missing/count
amounts reach their correct quantity guard; manual text and source links both survive;
partial lists retain unresolved items; duplicate consumption produces two contributions;
exact-product/supplement/recipe identity gates stay strict. Re-run the frozen list
suite plus package/simulator/static-analysis gates for substantive production Swift
changes. Existing private source originals and reference labels remain untouched.

This is exposed synthetic software evidence. It does not establish model quality,
physical dictation behaviour, persistent storage, real-user outcome quality or independent
acceptance. The initial evaluation phase changed tooling only; its failing evidence is preserved below the subsequent repair.

## Local repair, 2 October 2026

`FoodListImportService` now creates a separate `genericSearch` capture for the actual
search and supplies it through `GenericFoodSearchRequest.additionalEvidence`. The
original manual capture stays first, with its original descriptor, line number and
reviewed input method. The composition root and deterministic evaluation inject the
identifier generator; the initializer's random default preserves existing callers.
Duplicate manual/search evidence identifiers are rejected. Existing adapters retain
both selected-candidate links. `food_confirmation_v2` and exact identity admission
remain unchanged.

Regression tests exercise pasted and reviewed-speech text through explicit save and
reopen, preserve both captures and source nutrients, and check the typed quantity
errors with zero writes. The list reference v3 changes only the expected evidence
count to two captures per saved entry. Food selections, input lines, quantities,
expected save/block outcomes and errors, and all 39 daily nutrient totals are identical
to frozen reference v2. The observer checks the original manual capture by its ID;
it also requires saved generic-search evidence linked to the selected candidate.
Historical failing trials and frozen reference v2 remain available.

Validation outcome: seven of seven whole lists, fourteen of fourteen line outcomes
and seven of seven daily totals pass. Nine supported entries save; three unsupported
quantities reach their expected errors. All fourteen safeguard checks pass. The full
package reports 289 cases with one optional skip and zero failures; all 279 simulator
and 47 Python harness tests pass. Xcode static analysis, module boundaries and diff
check pass. The overall private report remains incomplete for the separately listed
unrun profiles. This is a local, uncommitted repair; no provider or device execution.
