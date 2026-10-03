# Generic food retrieval policy v5

The shared presentation policy penalises bounded unrequested form descriptors
(crumbled, sliced, diced, chopped and peeled) before ordinary-representation
bonuses. This prevents a `whole` bonus from promoting an unrequested form over a
simpler record. Primary-food and explicit specialisation handling retain
precedence. Explicitly requested forms incur no penalty. Other ordinary bonuses
and additional-term tiebreaks retain their previous order. A broader experiment
moving all descriptor counts ahead of ordinary bonuses failed an existing rice
contract and was narrowed; neither the contract nor references were relaxed.

For ranking only, ignore the exact parenthetical USDA Food Distribution Program
annotation. It identifies source coverage, not food form. No other parenthetical
text is erased. Original names, evidence, lexical eligibility, source identity,
preparation, quantity and nutrition admission remain intact. Unknown preparation
still cannot satisfy an explicit preparation constraint. No candidate is accepted
automatically and no catalogue bytes or nutrient values change.

## Architecture gate

Responsibilities remain in the existing pure application ranking policy, used by
both catalogue adapters and bundled composition. Dependency direction is unchanged;
no new abstraction, framework or provider is introduced. Ranking is the extension
axis; source identity, provenance, eligibility and conversion invariants remain
closed. Shared contract tests cover simple/form-specific ordering, explicit
requests, exact annotation removal, retained unknown annotations and existing
whole/white preferences. Real source and composition suites protect the consumers.

Versions advance to generic-representation-ranking-v5, cofid-generic-ranking-v11,
usda-generic-ranking-v12 and composite-generic-ranking-v7. Source/schema/lexical
and parser versions do not change. Ranking preference is a proposed generic
representation policy, not verified intake identity or a population-quality claim.

## Validation and run book

Run the shared policy and both adapter suites first, then the complete package
suite, simulator suite and unsigned Xcode static analysis. Preserve the preceding
private development run, freeze unchanged references and catalogue hashes in a
new outside-Git directory, and execute the offline retrieval probe. Report rank
changes with source-specific and composite denominators, preserving preparation
blocks and uncertainty. Re-run the original-text parser to verify it is unchanged.
Personal cases, source captures, labels and derived reports stay outside Git.

Final local validation: the complete package suite passed (287 reported tests,
one optional source replay skipped), 279 simulator tests passed without skips,
and unsigned Xcode analysis succeeded. The unchanged-reference private paired
comparison and source-search evidence are retained outside Git; their personal
case content and paths are intentionally absent from this document.
