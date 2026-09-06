# Development Notes

## Codex build experiment

This repository was developed with Codex as an experiment in agent-assisted iOS engineering. The figures below are recorded model-usage counters, not a measure of source-code size or unique conversation text. Codex repeatedly processes the growing task context, so cached input dominates the totals.

The original measurement covered the initial request through completion of local signing on 26 August 2026. It was captured as one aggregate and cannot now be divided honestly among its individual commits:

| Date | Feature or change | Commit | Individual usage |
| --- | --- | --- | ---: |
| 25 Aug | Steps MVP and real-device validation | `b56131e` | Included in initial aggregate |
| 25 Aug | Latest weight | `adc0946` | Included in initial aggregate |
| 25 Aug | Body composition | `3694a6d` | Included in initial aggregate |
| 25 Aug | RHR, HRV, sleep, active energy, exercise and workouts | `6e64669` | Included in initial aggregate |
| 25 Aug | Weight, RHR and HRV trends | `7d20c18` | Included in initial aggregate |
| 26 Aug | Body-fat fraction correction | `1f01cdb` | Included in initial aggregate |
| 26 Aug | Public-release cleanup and Diagnostics screen | `3910ada` | Included in initial aggregate |
| 26 Aug | Watch coverage and richer clipboard report | `0b9ab8d` | Included in initial aggregate |
| 26 Aug | Weight recording timestamp | `809c4b1` | Included in initial aggregate |
| 26 Aug | GitHub Actions iOS tests | `217a8a6` | Included in initial aggregate |
| 26 Aug | Synthetic simulator screenshot and clipboard example | `b804d39`–`14620c5` | Included in initial aggregate |
| 26 Aug | Private, ignored local signing configuration | `58da2e1` | Included in initial aggregate |
| **Initial aggregate** | **Main task plus linked internal review work** | `b56131e`–`58da2e1` | **30,667,943 tokens / $18.79** |

The initial aggregate comprised 30,622,876 input tokens, of which 29,055,616 were cached, and 45,067 output tokens. The main task accounted for 23,666,651 tokens and linked internal review work for 7,001,292 tokens.

Later work was measured as deltas over each implementation phase. These rows include linked internal review usage where it was recorded. Input is shown as total input with its cached portion in parentheses; uncached input is the difference.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 27 Aug | Development experiment note | `b2ed44b` | 2,016,064 (1,842,176) | 8,820 | 2,024,884 | $1.61 |
| 27 Aug | App icon design and integration | `7d15c9a` | 5,062,517 (4,871,296) | 9,280 | 5,071,797 | $2.90 |
| 27 Aug | Waist circumference and daily-first glucose summary | `bcedd3f` | 7,465,113 (7,303,552) | 19,600 | 7,484,713 | $3.96 |
| 27 Aug | Four-week waist trend | `2e53913` | 3,239,229 (3,100,928) | 10,466 | 3,249,695 | $2.00 |
| 30 Aug | Dynamic medication dose reporting | `da6d8e9` | 8,413,207 (8,010,496) | 27,835 | 8,441,042 | $5.37 |
| 30 Aug | Medication access fixes and iOS 26 CI | `d186ff7`–`8711d38` | 17,828,153 (17,526,528) | 27,144 | 17,855,297 | $8.76 |
| 31 Aug | VO₂ max and blood-oxygen summaries | `492b6bd` | 11,465,142 (11,167,488) | 29,772 | 11,494,914 | $6.25 |
| 1 Sep | Workout start dates and times | `c966efc` | 1,730,566 (1,425,664) | 4,624 | 1,735,190 | $1.88 |
| 1 Sep | Fixed `dd/MM/yyyy - HH:mm` workout format | `dee9264` | 1,570,784 (1,535,616) | 3,568 | 1,574,352 | $0.83 |
| 1 Sep | `FST` workout abbreviation | `a8b2aee` | 1,517,907 (1,488,128) | 1,818 | 1,519,725 | $0.75 |
| 1 Sep | Blood-pressure design and paired morning/evening reporting | `c68bba7` | 9,671,749 (9,414,912) | 47,980 | 9,719,729 | $5.75 |
| **Later work subtotal** |  | `b2ed44b`–`c68bba7` | **69,980,431 (67,686,784)** | **190,907** | **70,171,338** | **$40.06** |
| **Tracked total** | **Initial aggregate plus measured later phases** | `b56131e`–`c68bba7` | **100,603,307 (96,742,400)** | **235,974** | **100,839,281** | **$58.85** |

The API-equivalent column applies the same historical GPT-5.6 Sol promotional rates used for the original 27 August 2026 comparison: $4.00 per million uncached input tokens, $0.40 per million cached input tokens, and $20.00 per million output tokens. Internal review work used a non-public review model, so pricing it at the same rate is a comparison assumption rather than an actual price.

This work ran under a ChatGPT Pro subscription and was not billed through the API. The table generally excludes gaps devoted only to discussion or investigation; the blood-pressure row includes its directly preceding design discussion because that phase was measured as one session. It excludes the token-audit conversations themselves except for the committed development-note phase, and excludes this revision of the table. The figures should therefore be read as a bounded experiment, not a complete transcript census or a reproducible benchmark. Model pricing, caching, context size, review activity and implementation choices can all materially change the result. Check [current OpenAI model pricing](https://developers.openai.com/api/docs/models/gpt-5.6-sol) before making a later comparison.

## Astra: daily-export planning, 6 September 2026

Model: **`gpt-6-astra`**, confirmed in every recorded turn context before the accounting boundary. This is a whole-session planning capture, not an implementation phase or a comparison of model productivity.

Work covered: checked local/GitHub app status and CI; researched Apple Files, Drive replacement constraints and HealthKit export semantics; agreed same-day JSON reports for Claude Cowork's following-morning plan, one canonical file per reporting date, daily metric breakdowns, one daily weight and reuse of existing deterministic app summaries/trends. Produced `docs/daily-export-contract.md` with delivery slices, proposed policies, synthetic device acceptance criteria and a next-task prompt. Corrected the blanket completed-day description after checking body-fat and VO₂ max model windows. Deferred workout intervals and automation.

No application implementation, device installation, personal HealthKit validation, Drive replacement experiment, commit or push was performed. The contract was uncommitted at capture.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Daily JSON export research, design discussion, contract and handoff — GPT-6 Astra | Uncommitted planning document | 716,129 (699,520) | 4,699 | 720,828 | $1.10 |

Pricing corrected after checking [official GPT-6 Astra pricing](https://developers.openai.com/api/docs/models/gpt-6-astra) on 6 September 2026. This row assumes Standard API rates: $10.00/M uncached input, $1.00/M cached input and $50.00/M output. Calculation: 16,609 uncached input × $10/M = $0.166090; 699,520 cached input × $1/M = $0.699520; 4,699 output × $50/M = $0.234950; total **$1.100560**, rounded **$1.10**. Recorded cache-write tokens are zero. Maximum recorded request input before the boundary is 78,381 tokens, below Astra's 272K long-context pricing threshold; the cumulative session input is not a single request. Standard rates are a comparison assumption, not a claim about the Codex service tier or an actual subscription charge; Fast, Batch/Flex and separate tool fees are not included.

The initially recorded $0.44 was arithmetically correct at the historical Sol rates ($4.00/M, $0.40/M, $20.00/M), yielding exactly $0.440224, but was not Astra pricing. It is retained here only as a historical fixed-rate comparison. Earlier tables keep their original rates and totals. Adding the Astra-priced row gives **101,560,109 tracked tokens** and **$59.95** by summing the recorded rounded comparison amounts across those model/rate assumptions, not a model-performance benchmark.

### Astra vs Sol: same-token pricing comparison

Both columns price the **same measured Astra usage**. Sol was not run for this task; its column uses the ledger's historical Sol rates and does not predict the tokens, quality or time Sol would require.

This is only a comparison of rates applied to a fixed token count, not a benchmark of Astra against Sol. Sol could require fewer or more tokens to achieve the same outcome, so its actual task cost could differ from the figure shown. These numbers do not establish relative task cost, efficiency, quality or speed.

| Component | Measured tokens | Astra Standard | Sol historical comparison |
| --- | ---: | ---: | ---: |
| Uncached input | 16,609 | $10/M → $0.166090 | $4/M → $0.066436 |
| Cached input | 699,520 | $1/M → $0.699520 | $0.40/M → $0.279808 |
| Output | 4,699 | $50/M → $0.234950 | $20/M → $0.093980 |
| **Total** | **720,828** | **$1.100560 ≈ $1.10** | **$0.440224 ≈ $0.44** |

For this identical token mix, Astra's comparison cost is **2.5×** Sol's, a difference of **$0.660336 ≈ $0.66**. These are API-equivalent comparisons, not actual subscription charges. The Sol column is not additional usage and is not added to tracked totals.

Reproducible boundary: session `01a07695-9c61-71d0-bf22-2652c1bc9520`, local rollout `rollout-2026-09-06T12-58-31-01a07695-9c61-71d0-bf22-2652c1bc9520.jsonl` under `.codex/sessions/2026/09/06/`. Use the complete cumulative token-count event at line 212, **2026-09-06 12:32:55.166 UTC**, immediately after the new-session handoff answer and before the accounting request. No start baseline was captured: these are whole-session counters through that event. Run the existing `phase_usage.py` helper against a temporary prefix ending before the accounting request, with rates 10, 1 and 50 for the Astra Standard comparison (or 4, 0.40 and 20 to reproduce the historical comparison). The private rollout itself is not included in the repository.

Included: all top-level planning discussion, research, source inspection, contract creation and handoff through that boundary. No subagents or hosted reviews were used. Token counters cover the recorded Codex session; separate tool/service usage is not measured or estimated. Excluded: the accounting request and this entire accounting turn, ledger edits, final accounting response, future tasks and future implementation. Do not replace this frozen row with later live counters.

## Synthetic Files feasibility preparation, 6 September 2026

Model: **`gpt-6-astra`**, verified from the new session's recorded turn context, not inferred from the previous task. This bounded phase covers repository/contract inspection, device and Drive version discovery, a separate synthetic-only iOS harness, pure policy checks, unsigned simulator/device builds, static analysis and a device protocol/results record. The user confirmed Drive access in Files. Device installation and external test writes were awaiting explicit approval at this boundary; no provider replacement result is claimed.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Synthetic Files harness and feasibility preflight — GPT-6 Astra | Uncommitted local harness and notes | 924,407 (889,472) | 9,988 | 934,395 | $1.74 |

Uses the ledger's documented Astra Standard comparison assumptions: $10/M uncached input, $1/M cached input and $50/M output. Calculation: 34,935 × $10/M + 889,472 × $1/M + 9,988 × $50/M = **$1.738222**, rounded **$1.74**. This is model-specific API-equivalent pricing, not an actual ChatGPT subscription charge or a claim about the Codex service tier. Separate tool charges are not measured. Maximum recorded request input through the boundary was 65,096, below the ledger's stated Astra long-context threshold; cumulative input is not one request. Cache-write counters were zero. No Sol task was run. Any fixed-token Astra/Sol rate comparison is not a benchmark: either model could require fewer or more tokens for the same outcome.

Reproducible phase: session `01a076bb-d761-7033-aae0-d114220746ab`, rollout `rollout-2026-09-06T13-40-17-01a076bb-d761-7033-aae0-d114220746ab.jsonl` under `.codex/sessions/2026/09/06/`. Baseline captured before substantive inspection: line 27, **2026-09-06 12:40:33.108 UTC**, counters **96,948 input / 82,432 cached input / 251 output**. Frozen end: line 163, **2026-09-06 12:48:03.851 UTC**, counters **1,021,355 input / 971,904 cached input / 10,239 output**. Run `phase_usage.py` against a temporary prefix ending at that event with `--baseline 96948 82432 251 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. The private rollout is not included in the repository.

Includes this top-level session's inspection, preparation, validation and device-test coordination discussion between those counters. No subagents, reused tasks or hosted reviews were used. Excludes baseline-discovery overhead before the captured start, this accounting edit/check and final response, subsequent device execution and all other sessions/service usage. The previous planning row and its counters remain frozen. Adding this row to the previously recorded aggregate gives **102,494,504 tracked tokens** and **$61.69** by summing recorded rounded comparison amounts; those mixed rate assumptions are not productivity or quality evidence.

## Authorised synthetic harness installation attempt, 6 September 2026

The user authorised the proposed installation and dedicated-folder synthetic writes with “proceed”. The separate app was signed successfully after Xcode obtained its development profile. iOS rejected installation because the free-profile app limit was reached. No existing app was removed, no harness launch occurred and no Drive write ran. The feasibility results record now captures that blocker.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Signed synthetic harness; installation blocked — GPT-6 Astra | Uncommitted evidence and accounting notes | 566,204 (560,384) | 1,586 | 567,790 | $0.70 |

Model confirmed again from session turn metadata: `gpt-6-astra`. At the existing Astra Standard assumptions ($10/M uncached input, $1/M cached input, $50/M output), 5,820 × $10/M + 560,384 × $1/M + 1,586 × $50/M = **$0.697884**, rounded **$0.70** API-equivalent, not an actual subscription charge. This is not a model benchmark; either Astra or Sol could require fewer or more tokens for the same outcome.

Same session and rollout as the preparation row. Baseline: line 182, **2026-09-06 12:49:23.952 UTC**, **1,220,841 input / 1,168,384 cached input / 12,065 output**. Frozen end: line 237, **2026-09-06 13:00:50.243 UTC**, **1,787,045 input / 1,728,768 cached input / 13,651 output**. Reproduce from the rollout prefix through line 237 using `--baseline 1220841 1168384 12065 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes top-level signing, installation attempt and coordination through that end event. Excludes this ledger edit, final handoff, subsequent work and separate service usage. No subagents or hosted reviews. Prior frozen rows remain unchanged. Tracked total becomes **103,062,294 tokens / $62.39**, summing recorded rounded comparison amounts.

## Synthetic harness installed, 6 September 2026

After separate explicit approval, PacePromptEvaluation was uninstalled. The signed synthetic harness was then successfully installed and launched on SiPhone. This phase ends at the first-save operator prompt; no Files/Drive result has yet been reported.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Authorised app removal, harness installation and launch — GPT-6 Astra | Uncommitted evidence/accounting notes | 381,102 (378,880) | 753 | 381,855 | $0.44 |

Model reverified from session metadata: `gpt-6-astra`. Existing Astra Standard assumptions give 2,222 × $10/M + 378,880 × $1/M + 753 × $50/M = **$0.438750**, rounded **$0.44** API-equivalent, not subscription charges. No fixed-token rate comparison establishes a model benchmark; either model could need fewer or more tokens.

Same rollout/session as above. Baseline line 257, **2026-09-06 13:01:59.589 UTC**: **2,009,631 input / 1,947,520 cached input / 15,282 output**. Frozen end line 294, **2026-09-06 13:03:41.223 UTC**: **2,390,733 input / 2,326,400 cached input / 16,035 output**. Reproduce from that prefix with `--baseline 2009631 1947520 15282 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes top-level device operations and initial operator coordination; excludes subsequent evidence/ledger edits, final response, later testing and separate service usage. No subagents or hosted review. Earlier rows remain frozen. Tracked total: **103,444,149 tokens / $62.83**, summing recorded rounded comparison amounts.

## Copy-export failure evidence, 6 September 2026

Recorded the operator-confirmed cancellation result and Drive web screenshot showing two same-name files after the actual evening save. Corrected the sequence: the earlier unchanged morning JSON followed cancellation, not a failed replacement attempt. Rejected this copy-export route at the uniqueness gate and proposed a bounded directory-access replacement experiment. No further provider writes or implementation ran.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Record duplicate-file failure and next storage experiment — GPT-6 Astra | Uncommitted evidence/accounting notes | 165,764 (161,920) | 1,620 | 167,384 | $0.28 |

Model verified from recorded turn metadata: `gpt-6-astra`. Existing Astra Standard rate assumptions ($10/M uncached input, $1/M cached input, $50/M output) yield **$0.281360**, rounded **$0.28** API-equivalent, not subscription charges. A fixed-token Astra/Sol comparison is not a benchmark; either model could use fewer or more tokens for the same result.

Same rollout/session as above. Baseline line 360, **2026-09-06 13:44:37.750 UTC**, **3,024,431 input / 2,954,752 cached input / 18,047 output**. Frozen end line 380, **2026-09-06 13:48:05.853 UTC**, **3,190,195 input / 3,116,672 cached input / 19,667 output**. Reproduce using that prefix and `--baseline 3024431 2954752 18047 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes evidence inspection and results-document update within this boundary. Earlier operator-guidance turns between the prior frozen row and this baseline are excluded, not estimated. Also excludes this ledger edit/check, final response and future work. No subagents or hosted reviews; separate service usage is unmeasured. Earlier frozen rows remain unchanged. Tracked total: **103,611,533 tokens / $63.11**, summing recorded rounded comparison amounts.

## Directory-route harness, 6 September 2026

Replaced the rejected copy-export UI with folder selection and coordinated synthetic-file updates in a fresh test folder. Added local filesystem integration checks and updated the protocol/evidence. Local checks, simulator build, analysis and signing passed. Build 2 installed successfully; automatic launch was blocked by the locked iPhone. Directory-provider selection and writes remain untested at the boundary.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Directory-route synthetic harness, checks and installation — GPT-6 Astra | Uncommitted harness and notes | 1,184,922 (1,166,592) | 6,346 | 1,191,268 | $1.67 |

Model verified from session metadata: `gpt-6-astra`. Existing Astra Standard comparison rates ($10/M uncached input, $1/M cached input, $50/M output) give 18,330 × $10/M + 1,166,592 × $1/M + 6,346 × $50/M = **$1.667192**, rounded **$1.67**. API-equivalent only, not subscription charges. Fixed-token Astra/Sol comparisons are not benchmarks: either model could need fewer or more tokens for the same outcome.

Same session/rollout as above. Baseline line 417, **2026-09-06 13:52:21.403 UTC**, **3,623,786 input / 3,545,856 cached input / 21,112 output**. Frozen end line 511, **2026-09-06 13:57:12.263 UTC**, **4,808,708 input / 4,712,448 cached input / 27,458 output**. Reproduce using that prefix and `--baseline 3623786 3545856 21112 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes top-level source/API inspection, implementation, checks, signing/installation, protocol updates and operator coordination within the boundary. Excludes gaps since the prior frozen row, this accounting edit/check and final response, future device results and separate service usage. No subagents or hosted review. Earlier rows remain frozen. Tracked total: **104,802,801 tokens / $64.78**, summing recorded rounded comparison amounts.

## Existing-file harness, 6 September 2026

Operator corrected the directory result: Drive was greyed out. Following approval, build 3 adds existing JSON open-in-place selection and coordinated replacement, preserving previous evidence. Added local replacement/no-op/stale/failure/unknown-content checks. Checks, clean simulator build/analysis and signing passed; installed and launched. The initial simulator SDK-cache build stalled and was stopped after the clean build passed. Provider selection/update remains pending; initial daily creation is unresolved.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Existing-file synthetic probe, checks and installation — GPT-6 Astra | Uncommitted harness and notes | 1,339,139 (1,327,872) | 4,411 | 1,343,550 | $1.66 |

Model confirmed from turn metadata: `gpt-6-astra`. At existing Astra Standard assumptions ($10/M uncached input, $1/M cached input, $50/M output), 11,267 × $10/M + 1,327,872 × $1/M + 4,411 × $50/M = **$1.661092**, rounded **$1.66** API-equivalent, not subscription charges. Any fixed-token comparison with Sol is not a benchmark: either model could need fewer or more tokens.

Same session/rollout as above. Baseline line 551, **2026-09-06 14:12:16.352 UTC**: **5,333,468 input / 5,233,792 cached input / 29,104 output**. Frozen end line 646, **2026-09-06 14:17:35.876 UTC**: **6,672,607 input / 6,561,664 cached input / 33,515 output**. Reproduce from that prefix using `--baseline 5333468 5233792 29104 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes top-level implementation, validation, device operations and coordination through the boundary. Excludes intervening discussion before baseline, this ledger edit/check, final response, future observations and separate service usage. No subagents or hosted review. Earlier rows remain frozen. Tracked total: **106,146,351 tokens / $66.44**, summing recorded rounded comparison amounts.

## Secure Drive implementation planning, 6 September 2026

Inspected current GitHub issues (no daily-export issue found), researched current OAuth/Picker/retry authority, revised the daily contract and narrow repository-rule exception, consolidated operator test evidence, and prepared the secure Drive implementation plan and issue body. No Google implementation or Cloud configuration ran. Issue publication awaits the user's decision to create a new issue or identify an existing one; no unrelated issue was edited.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Secure Drive plan, evidence and issue preparation — GPT-6 Astra | Uncommitted planning changes | 1,147,247 (1,125,760) | 6,907 | 1,154,154 | $1.69 |

Model verified from session metadata: `gpt-6-astra`. Existing Astra Standard rates ($10/M uncached input, $1/M cached input, $50/M output) yield 21,487 × $10/M + 1,125,760 × $1/M + 6,907 × $50/M = **$1.685980**, rounded **$1.69** API-equivalent, not subscription charges. No fixed-token Astra/Sol comparison is a benchmark; either model could require fewer or more tokens.

Same rollout/session as above. Baseline line 846, **2026-09-06 14:36:13.298 UTC**, **9,304,256 input / 9,172,096 cached input / 37,031 output**. Frozen end line 917, **2026-09-06 14:43:42.832 UTC**, **10,451,503 input / 10,297,856 cached input / 43,938 output**. Reproduce from that prefix using `--baseline 9304256 9172096 37031 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`. Includes top-level investigation, planning and draft preparation through the boundary. Excludes earlier operator/research discussion since the previous row, this ledger edit/check and final response, later issue publication or implementation, and separate service usage. No subagents or hosted reviews. Earlier rows remain frozen. Tracked total: **107,300,505 tokens / $68.13**, summing recorded rounded comparison amounts.

## Secure Drive slice-A local implementation, 6 September 2026

Implemented the uncommitted synthetic-only consent and destination harness. The
phase resolved the Picker compatibility gate, pinned AppAuth-iOS 2.1.0, added
system authentication with exact `drive.file` admission, this-device-only Keychain
state, account-partitioned destination bindings, create/select folder flows,
folder/account/write checks, local sign-out versus remote revocation, and a
least-privilege denial probe. It also added pure/mocked checks and updated the
contract, plan, harness guide and evidence. No Google grant, folder mutation,
device installation, HealthKit query, daily JSON transport, commit or push ran.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Secure Drive slice-A local harness — GPT-5.6 Sol | Uncommitted harness and notes | 8,195,255 (7,905,408) | 35,626 | 8,230,881 | $5.03 |

Model verified from this session's turn metadata: `gpt-5.6-sol`. Applying the
ledger's historical Sol comparison assumptions ($4/M uncached input, $0.40/M
cached input and $20/M output), 289,847 × $4/M + 7,905,408 × $0.40/M +
35,626 × $20/M = **$5.0340712**, rounded **$5.03** API-equivalent. This is not
an actual ChatGPT subscription charge or a model benchmark; separate tool/service
charges are not measured.

Session `01a07734-1a44-7520-8bfd-fb63cbe26249`, rollout
`rollout-2026-09-06T15-51-38-01a07734-1a44-7520-8bfd-fb63cbe26249.jsonl`.
Baseline line 33, **2026-09-06 14:52:20.089 UTC**: **114,285 input / 86,656
cached input / 704 output**. Frozen end line 430, **2026-09-06 15:13:10.504
UTC**: **8,309,540 input / 7,992,064 cached input / 36,330 output**. Reproduce
with `--baseline 114285 86656 704 --uncached-input-rate 4
--cached-input-rate 0.40 --output-rate 20`.

Includes the top-level repository/issue/source inspection, current official-source
research, implementation, package/API verification, local validation and status
discussion between those counters. No subagents, reused tasks or hosted reviews
were used. Excludes baseline-discovery work before the captured start, this ledger
edit/check, the final response, all future Cloud/device/operator work and separate
service usage. Every earlier row remains frozen. Tracked total becomes
**115,531,386 tokens / $73.16**, summing recorded rounded comparison amounts.

## Secure Drive slice-A external configuration and SiPhone acceptance, 6 September 2026

Configured the user-owned Google Cloud project with only the Drive and Picker APIs,
an External/Testing audience, the exact `drive.file` scope and the synthetic iOS
client. Private client/account/signing values remain out of the repository; no
client secret was requested or stored. Signed and installed build 4 on the
authorised SiPhone, then coordinated consent, cancellation, secure restoration,
local sign-out, create-folder validation and revocation checks. The mandatory
existing-folder Picker path failed because the special iOS flow allowed navigation
into an empty folder but offered no way to select the folder itself. Work stopped
at that gate without broader permissions, hosting, HealthKit, daily JSON, slice B,
commit or push. Provider, device and local evidence were recorded separately.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Slice-A Cloud/device acceptance and Picker stop gate — GPT-6 Astra | Uncommitted configuration/evidence notes | 16,863,876 (16,552,192) | 25,294 | 16,889,170 | $20.93 |

Model confirmed from session metadata: `gpt-6-astra`. At the ledger's Astra
Standard comparison assumptions ($10/M uncached input, $1/M cached input and
$50/M output), 311,684 × $10/M + 16,552,192 × $1/M + 25,294 × $50/M =
**$20.933732**, rounded **$20.93** API-equivalent, not an actual ChatGPT
subscription charge. This is not a model benchmark; separate Google/tool charges
are not measured or estimated.

Session `01a0774b-ad41-7220-b4b9-30ac08ce7c2c`, rollout
`rollout-2026-09-06T16-17-23-01a0774b-ad41-7220-b4b9-30ac08ce7c2c.jsonl`.
Baseline line 49, **2026-09-06 15:17:54.286 UTC**: **169,405 input / 150,144
cached input / 1,030 output**. Frozen end line 1163, **2026-09-06 16:06:51.386
UTC**: **17,033,281 input / 16,702,336 cached input / 26,324 output**.
Reproduce from that prefix with `--baseline 169405 150144 1030
--uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`.

Includes the top-level Cloud/browser configuration, local inspection and checks,
device build/install/launch work, operator coordination, synthetic Drive mutations
and evidence updates between those counters. No subagents, reused tasks or hosted
reviews were used. Excludes baseline-discovery work before the captured start,
this accounting edit/check, the final handoff, future hosted-Picker design and
separate service usage. Every earlier row remains frozen. Tracked total becomes
**132,420,556 tokens / $94.09**, summing recorded rounded comparison amounts.

## Slice-A Picker recovery and final acceptance follow-up, 6 September 2026

The operator discovered that changing the iOS Picker filter to **Folder** made the
dedicated existing folder selectable. Build 4 accepted and validated it, so no
hosted Picker or broader permission was required. The unrelated disposable file
was denied and externally revoked credentials failed closed with no export written.
The Picker's scroll/tap behaviour was unreliable and revoked access produced only a
generic failure message. Google rejected the only proposed second address as
ineligible for test-user designation; the operator chose to skip two-account
switching. Slice A therefore remains incomplete under the all-checks rule.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Picker recovery, denial/revocation evidence and two-account skip — GPT-6 Astra | Uncommitted evidence/accounting notes | 2,896,498 (2,874,880) | 8,811 | 2,905,309 | $3.53 |

Model confirmed from session metadata: `gpt-6-astra`. At the documented Astra
Standard assumptions ($10/M uncached input, $1/M cached input and $50/M output),
21,618 × $10/M + 2,874,880 × $1/M + 8,811 × $50/M = **$3.531610**,
rounded **$3.53** API-equivalent, not an actual subscription charge or a model
benchmark. Separate Google/tool charges are not measured or estimated.

Same session and rollout as the preceding row. Baseline is that row's frozen end,
line 1163, **2026-09-06 16:06:51.386 UTC**: **17,033,281 input / 16,702,336
cached input / 26,324 output**. Frozen end line 1369, **2026-09-06 16:26:35.855
UTC**: **19,929,779 input / 19,577,216 cached input / 35,135 output**.
Reproduce from that prefix with `--baseline 17033281 16702336 26324
--uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`.

Includes the preceding accounting edit/final handoff that was outside the previous
boundary, subsequent operator/device results, test-user eligibility discussion,
evidence correction and final checks through this boundary. No subagents, reused
tasks or hosted reviews were used. Excludes this accounting edit/check, the final
response, future work and separate service usage. Every earlier row remains frozen.
Tracked total becomes **135,325,865 tokens / $97.62**, summing recorded rounded
comparison amounts.

## Slice-A two-account completion, 6 September 2026

An eligible second Google test account was subsequently available. Build 4 created
and validated its separate synthetic destination. Across local sign-out and
reconnection, the original account restored only its original destination and the
second account restored only its second destination. This completed the last
required two-account isolation check, so slice A is accepted with the previously
recorded Picker usability and generic revoked-access-message limitations. No slice
B work, HealthKit query, daily JSON, commit or push ran.

| Date | Feature or change | Commit(s) | Input tokens (cached) | Output tokens | Total tokens | API-equivalent |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 6 Sep | Two-account isolation and slice-A acceptance — GPT-6 Astra | Uncommitted evidence/accounting notes | 1,571,727 (1,564,288) | 3,741 | 1,575,468 | $1.83 |

Model confirmed from session metadata: `gpt-6-astra`. At the documented Astra
Standard assumptions ($10/M uncached input, $1/M cached input and $50/M output),
7,439 × $10/M + 1,564,288 × $1/M + 3,741 × $50/M = **$1.825728**,
rounded **$1.83** API-equivalent, not an actual subscription charge or a model
benchmark. Separate Google/tool charges are not measured or estimated.

Same session and rollout as the preceding rows. Baseline is the preceding row's
frozen end, line 1369, **2026-09-06 16:26:35.855 UTC**: **19,929,779 input /
19,577,216 cached input / 35,135 output**. Frozen end line 1468,
**2026-09-06 16:33:39.365 UTC**: **21,501,506 input / 21,141,504 cached input /
38,876 output**. Reproduce from that prefix with `--baseline 19929779 19577216
35135 --uncached-input-rate 10 --cached-input-rate 1 --output-rate 50`.

Includes the preceding accounting edit/final handoff outside its prior boundary,
the final two-account operator checks, evidence correction and final validation
through this boundary. No subagents, reused tasks or hosted reviews were used.
Excludes this accounting edit/check, the final response, future work and separate
service usage. Every earlier row remains frozen. Tracked total becomes
**136,901,333 tokens / $99.45**, summing recorded rounded comparison amounts.
