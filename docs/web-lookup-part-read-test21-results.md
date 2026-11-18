# Web lookup at the new page bounds: test 21 live measurement (experiment, #508)

Status: **experiment, run on 18 November 2026 against `main` at `c55f7233` (PR 519 merged).** This is the live measurement required by test 21 of [the part-read pages contract](web-lookup-part-read-pages-v1-proposal.md) (section 12). It is a separately labelled experiment: it changes no app code, test or fixture, and it decides nothing beyond test 21's own rule. The owner approved running it with their own OpenRouter key on 18 November 2026.

**Verdict: pass.** No timeout or refusal attributable to size occurred on either model route. All 22 provider requests across 12 reviews returned HTTP 200 with finish reason `stop`.

**Owner acceptance (18 November 2026).** The owner accepted this result as test 21's pass, knowing its two gaps: no real competing-panel page was found, so that case rests on the constructed page C2 (which test 21's text does not name) and on the contract tests; and offer row 2 (a suggestion with competing panels beside it) was not reached live and is covered only by the contract tests. The owner's device check of the next build exercises the device-report page itself.

## 1. Method

The harness is a scratch executable kept outside the repository, built against a copy of `Packages/FoodLedgerKit` at the merged head. It composes the production pipeline exactly as `FoodLedgerCompositionRoot` does:

- `OpenRouterFoodProvider(extractionRoute: .grok, selectionRoute: .applicability, retry: .live)` with the live transport;
- `GenericFoodProposalReviewer` with `PublicFoodSourceCapture` and its default review timeout;
- the supplied-address route (`review(foodTerms:sourceURL:key:)`), which grants the part-read permission;
- the production offer (`review.offer`), the v3 writer (`ReviewedFoodProposalConfirmation.prepare`) and the reopen admission (`FoodReviewedWebProposalPolicy.restoredSourceCandidate`).

The only additions are measuring wrappers. The transport wrapper records each request's route, duration, HTTP status, served model, token counts (prompt, completion, reasoning) and the cost OpenRouter reports, and refuses any request to a host other than `openrouter.ai`. The capture wrapper records blocks, characters and whether the page was read in part. The key was read at run time into the child process environment only; it was never printed or written, and the harness refuses to write any output containing it.

Reopen and diary-list timing used a second scratch test in the package's contract test target. It saved each prepared entry through the in-memory store and the GRDB store, with synthetic Confirm answers for the food details (as in `ReviewManifestV2ContractTests`) and the source nutrients unchanged. It then timed `FoodConfirmationService.reopen` and the diary list's per-row rebind (`foodConfirmation(logItemID:)` plus `isEstimate`), five times each, and recorded the median. These are Mac timings and prove software behaviour only.

Where the offer was empty (rows 4 and 5), nothing reaches Confirm in the app, so the first run records no manifest. To still measure manifest size on those larger whole pages, W1, W4 and W5 were run a second time with an off-journey step: if nothing is offered, prepare the first choosable bound candidate anyway. Both W1 and W4 were offered row 1 on the second run, so the off-journey step did not apply and their figures are real journey figures. On W5 the writer refused the off-journey step with `invalidSelection` because the candidate was never offered, which is the production guard working as intended.

Attempts left out of the figures:

- one W1 attempt that failed with HTTP 401 because the first key file read was stale; the working key was used for every run below;
- first attempts at C1 and C2 that failed in the harness before any request, because the harness passed `text/html; charset=utf-8` to the projector where production passes the bare media type. This was fixed in the harness only.

## 2. Pages

The pages are fresh. Section 1's measurement did not record its address list in the repository, so every host seen in that session's transcript was avoided (89 hosts, including Ocado, Marks & Spencer, Morrisons, Tesco, Open Food Facts and The Organic Protein Company). About 35 further public addresses were tried while choosing the set; most either refused automated reads (for example Holland & Barrett, Myprotein, Boots, Amazon) or were well under the old bounds.

| Id | Page | Kind |
| --- | --- | --- |
| W1 | https://www.sainsburys.co.uk/groceries/product/sainsburys-double-pepperoni-thin-pizza-339g | real, between old and new bounds (block count) |
| W2 | https://www.sainsburys.co.uk/groceries/product/sainsburys-thin-crispy-four-cheese-pizza-354g | real, between bounds (block count) |
| W3 | https://www.costco.co.uk/Food-Drink/Food-Cupboard/Cereals/Quaker-Oat-So-Simple-Original-Porridge-Sachets-50-x-27g/p/1305937 | real, between bounds (block count); no nutrition panel in the HTML |
| W4 | https://www.bulk.com/uk/products/pure-whey-protein/bpb-wpc8-0000 | real, between bounds (character count) |
| W5 | https://www.bulk.com/uk/products/vegan-protein-powder/bpb-vpro-0000 (redirects to a sibling address on the same host) | real, between bounds (character count) |
| W6 | https://uk.huel.com/products/huel-black-edition | real, between bounds (character count) |
| W7 | https://uk.huel.com/products/huel-ready-to-drink | real, between bounds (character count); no full panel |
| C1 | **constructed**, served under the W1 address | beyond the new bounds |
| C2 | **constructed**, served under the W4 address | competing panels |

The constructed pages were never fetched from a network; the harness projected local bytes through the production projector with the same part-read permission.

- **C1** is W1's real page bytes with 1,400 aisle links added in a navigation list before `</body>` (2,049,035 bytes). Without permission it is refused (`responseTooLarge`); with permission it is read in part: 35 of 2,223 blocks and 5,397 of 38,296 characters kept, under `food-document-block-selection-v1`.
- **C2** is W4's real page bytes with a second nutrition table added under the heading "Nutrition (batch 2)": a copy of the page's own table with every value changed (for example protein 65 g to 72 g per 100 g). It projects whole at 392 blocks and 63,370 characters.

No real public page beyond the new bounds was found: the largest real product page was W3 at 1,301 blocks. No real page with genuinely competing panels was found either. Test 21 allows a constructed beyond-bounds page; it does not mention construction for competing panels, so C2 is a limit of this experiment (section 5).

## 3. Figures

Review time is the whole reviewer call, from start to result. Route G is the extraction route (`x-ai/grok-4.7` served); route A is the applicability (selection) route (`openai/gpt-6-luna` served). Tokens are prompt / completion (of which reasoning). Each route made one request per review; the provider's own attempt timeout was 90 s.

| Id | Blocks / characters read | Review s | Route G tokens | Route G s | Route A tokens | Route A s | Cost USD |
| --- | --- | ---: | --- | ---: | --- | ---: | ---: |
| W1 | 837 / 25,445 | 37.1 | 24,175 / 2,471 (1,653) | 33.0 | 18,793 / 51 | 2.1 | 0.064 |
| W2 | 833 / 26,834 | 49.6 | 24,365 / 4,543 (3,755) | 46.4 | 18,951 / 50 | 1.8 | 0.077 |
| W3 | 1,301 / 21,508 | 11.9 | 29,903 / 288 (261) | 11.1 | not called | | 0.060 |
| W4 | 383 / 63,071 | 32.6 | 36,125 / 2,620 (1,848) | 30.7 | 32,931 / 52 | 1.6 | 0.090 |
| W5 | 387 / 33,994 | 49.4 | 22,387 / 2,924 (2,033) | 47.1 | 20,480 / 51 | 2.1 | 0.063 |
| W6 | 448 / 48,074 | 63.1 | 30,547 / 2,954 (2,570) | 60.9 | 27,364 / 50 | 1.7 | 0.076 |
| W7 | 480 / 37,077 | 54.5 | 26,520 / 3,238 (2,794) | 54.0 | not called | | 0.067 |
| C1 | 35 of 2,223 / 5,397 of 38,296 (part read) | 43.5 | 6,566 / 3,711 (2,957) | 41.6 | 4,190 / 50 | 1.5 | 0.034 |
| C2 | 392 / 63,370 | 60.9 | 36,415 / 3,808 (3,073) | 57.8 | 33,133 / 51 | 2.9 | 0.098 |
| W1, second run | 819 / 25,391 | 58.2 | 23,873 / 3,499 (2,735) | 54.0 | 18,402 / 50 | 2.7 | 0.069 |
| W4, second run | 383 / 63,119 | 44.2 | 36,152 / 3,267 (2,470) | 41.5 | 33,153 / 50 | 2.3 | 0.094 |
| W5, second run | 387 / 33,994 | 29.3 | 22,387 / 2,543 (1,707) | 26.9 | 20,439 / 51 | 2.2 | 0.061 |

Total reported provider cost: USD 0.854 (route G 0.825, route A 0.029). Block and character counts vary slightly between runs of the same page because the live page changed between fetches.

Binding, offer and Confirm:

| Id | Bound candidates | Selection | Offer row | Confirm | Manifest bytes | Reopen restored |
| --- | --- | --- | --- | --- | ---: | --- |
| W1 | 2 (per 100 g; per half pizza), both choosable | `clarify` | 4, nothing offered | not reached | | |
| W2 | 2 (per 100 g; per half pizza) | `c1` | 1 | prepared, per 100 g | 186,893 | yes |
| W3 | none (no panel in the page) | not run | 5 | not reached | | |
| W4 | 2 (per 100 g; per 35 g serving) | `clarify` | 4 | not reached | | |
| W5 | 2 (per 100 g; per 35 g serving) | `clarify` | 4 | not reached | | |
| W6 | 1 (per 90 g serving, energy only) | `c1` | 1 | prepared | 151,168 | yes |
| W7 | 1, not choosable (no basis) | not run | 5 | not reached | | |
| C1 (part read) | 2 (per 100 g; per serving) | `c1` | 1 | prepared, per 100 g | 19,704 | yes |
| C2 (competing) | 2, both `conflictingCandidates` | `clarify` | 3: warning, no preselection, pick required | prepared after a pick (the first offered candidate) | 150,036 | yes |
| W1, second run | 2 | `c1` | 1 | prepared | 186,005 | yes |
| W4, second run | 2 | `c1` | 1 | prepared | 144,309 | yes |
| W5, second run | 2 | `clarify` | 4 | off-journey prepare refused (`invalidSelection`) | | |

Proposals bound on every whole page with a panel and on the part-read page. Offer rows 1, 3, 4 and 5 were reached; row 2 (suggestion plus competing candidates) was not.

Reopen and diary-list timing (median of five, seconds; memory store / GRDB store):

| Entry | Manifest bytes | Save | Reopen | Diary-list row |
| --- | ---: | --- | --- | --- |
| C1 | 19,704 | 0.082 / 0.086 | 0.015 / 0.016 | 0.027 / 0.029 |
| C2 | 150,036 | 0.202 / 0.208 | 0.042 / 0.044 | 0.074 / 0.077 |
| W1, second run | 186,005 | 0.167 / 0.173 | 0.040 / 0.042 | 0.066 / 0.068 |
| W2 | 186,893 | 0.194 / 0.198 | 0.044 / 0.047 | 0.075 / 0.078 |
| W4, second run | 144,309 | 0.156 / 0.160 | 0.033 / 0.036 | 0.058 / 0.060 |
| W6 | 151,168 | not measured | | |

W6's entry has a serving basis; its save needs a measured amount, which the synthetic Confirm answers did not supply, so it was not timed. No manifest exceeded 1 MB; the largest was 186,893 bytes.

## 4. Reading against test 21

- **Timeouts:** none. The longest review was 63.1 s (W6) and the longest single request 60.9 s, inside the 90 s attempt timeout. Route G's duration follows its reasoning tokens more than page size: W3, at 29,903 prompt tokens, took 11.1 s with 261 reasoning tokens.
- **Refusals:** none from either provider route. The only refusal in the live runs was the writer refusing the off-journey prepare on W5, a guard and not size. The projector's refusal of C1 without the part-read permission was seen only in an offline check before the runs; on the supplied-address route the permission is granted and C1 was read in part.
- **Part-read page:** C1, a page beyond both bounds, was read in part, bound, reached row 1 and Confirm, and reopened.
- **Competing panels:** C2 reached row 3 with the warning and a required pick, was taken through to Confirm, and reopened.
- **Selection variability:** W1 and W4 gave `clarify` (row 4) on one run and `c1` (row 1) on the next, with similar inputs. That is the selection model's run-to-run variation on pages whose two candidates are two bases of one product; it is not a size effect, but it means a person sees nothing offered on some runs.

## 5. Limits and what is still unverified

- No real page beyond the new bounds and no real competing-panel page was found; C1 and C2 are constructed from real page bytes and labelled. C2's construction is not named in test 21's text.
- Offer row 2 was not reached.
- Every figure comes from a Mac with a scratch harness, not the app. The Confirm screen, reopen and diary list were not exercised on a device or in the simulator; device timing for 150 to 190 KB manifests is unmeasured.
- W6's reopen and diary-list timing was not measured.
- One run per page (two for W1, W4 and W5), so the timing figures are single samples; the provider's served model and routing may change.
- Section 1's address list is not in the repository, so freshness rests on avoiding the hosts recorded in that session's transcript.
