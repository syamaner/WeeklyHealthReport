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
