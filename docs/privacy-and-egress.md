# Privacy and data egress

This is the single engineering list of what may leave the device, where it goes and which contract governs it. The user-facing statement is [`privacy-policy.txt`](privacy-policy.txt); keep both consistent. Anything not listed here must not leave the device.

## Stays on the device unless the user sends it

- **HealthKit data** leaves only inside a Daily JSON export the user reviews and sends, or a report or Today screen the user copies, shares or screenshots (including the today-so-far Health values in Today's Full Page).
- **Notes** leave only inside the Daily JSON export for their day. Today's Full Page shows only today's note count, never note text.
- **The food log** for one selected day leaves only inside the separate food daily export file the user reviews and sends to Google Drive ([food-daily-export-contract-v1.md](food-daily-export-contract-v1.md)); the health Daily JSON export never contains it. Otherwise the food log, intake history, saved foods, favourites, drafts and inventory stay local, except an inventory backup file the user explicitly exports to a location they choose, and Today's Full Page when the user takes a screenshot and chooses Full Page: it contains today's food totals and quick-add favourite names and default amounts. The Health report's Copy all and Full Page contain the Food and water section's logged-day counts and averages ([health-food-and-water-v1.md](health-food-and-water-v1.md)). HealthKit food writes remain a separate plan (#97).
- **Audio** never leaves. Speech recognition is on-device only.
- **Label photos** leave only as the single prepared image sent when the user taps Read label with AI. The image kept with a logged entry stays on the device; it is not in the Drive food export or backups.

HealthKit access is read-only: authorisation `toShare` stays empty. No analytics, tracking, crash SDK, backend, account system or background delivery.

Source datasets bundled with the app (CoFID 2021, USDA FoodData Central, TFDA and Ciqual 2025) are downloaded by a developer, outside the app, before the projection is built. That download carries no user data and is not app egress; the app reads only the bundled, hash-checked projections and makes no request to those publishers. Owner approval: 4 November 2026, on #384 ([ciqual-2025-admission-v1.md](ciqual-2025-admission-v1.md) section 1.3).

Developer tooling for Your food database ([personal-food-catalogue-import-v1.md](personal-food-catalogue-import-v1.md)) runs on the owner's Mac, not in the app, and is not app egress. Its scripts send to Open Food Facts only (a) product titles from the owner's own receipts and from intake items that name a brand, with pack sizes removed, (b) generic food names, and (c) barcodes of chosen matches. They never send receipt text, notes, amounts, prices, addresses or identifiers, and all requests go through the skill's paced client (below the published limit, with backoff and Retry-After). Receipt titles come only from receipt item lines, never headers, after the extractor's privacy gate, and every query also passes an outbound gate (no currency, prices, emails, postcodes, long numbers, honorific names, street addresses or order and payment words, and at least one known food word, or Chinese text containing a known Chinese food fragment). Because a word list cannot recognise every personal name, no search query is sent until the owner has approved that exact query: the scripts list every planned query in a pending file and stop before any network call, then send only approved queries and never declined ones. Barcode lookups for chosen products send only digits taken from Open Food Facts' own results and need no separate approval. A product page the owner names is read once with the agent's web-fetch tool. What the agent reads reaches the agent's model provider: the owner's notes, label and receipt photos, CSV header rows, product pages the owner names, and the food titles the agent maps or shows the owner for approval; only when the owner asks. Owner approval: 7 November 2026.

Personal food database evaluation drafting ([evaluation plan revision 5](personal-food-database-evaluation-v1.md),
section 9 decision 8) is local processing on the owner's Mac. Codex may direct offline scripts to
read the pinned release, initial review rows and unsplit queries and write private drafts and
proposals. Only aggregate counts and hashes may be returned to the agent through tool results,
console, chat or handover. The underlying catalogue contents, titles, brands, query text, expected
answers, review-sheet rows and proposals are not approved for model-provider access: never include
them in prompts, file-display output, error messages or external review payloads. Drafting authority
does not approve a food query to any external service. The owner validates every row; nutrient
value-against-pack checks remain exclusively the owner's. This narrows the evaluation workflow to
local scripts and adds no destination or private-data payload to the allowed egress list. Owner
workflow approval: 8 November 2026; draft contents and plan acceptance remain pending.

## Allowed egress

| Destination | What is sent | When | Contract |
|---|---|---|---|
| Clipboard, share sheet or the iOS screenshot editor | The report text, or a Full Page PDF of Health (the report) or Today (today's food totals, quick-add favourite names and amounts, today's note count and today-so-far Health values), created in memory; or a misread report for a pasted nutrition label (the pasted label text, the values read from it, and the parser, gate, check and conversion versions), as previewed and edited by the user | Only when the user chooses Copy all, Share, a screenshot's Full Page, or Report a misread, and then saves or shares it; the user picks the destination in the system share sheet and can cancel; the app has no destination of its own and nothing is sent automatically | [app-reference.md](app-reference.md), [pasted-nutrition-label-v1.md](pasted-nutrition-label-v1.md) |
| A file location the user chooses | The inventory backup file | Only when the user chooses to export a backup | [food-library-storage-and-backup-decision.md](food-library-storage-and-backup-decision.md) |
| Google Drive (`drive.file`) | The exact reviewed Daily JSON bytes (health data, selected-source nutrition and that day's notes), and, when the user keeps Food log on, the exact reviewed food daily JSON bytes for the same day (log entries, nutrient values with their sources, daily totals), each with minimal export-identity metadata | Only when the user chooses Export | [daily-export-contract.md](daily-export-contract.md), [food-daily-export-contract-v1.md](food-daily-export-contract-v1.md), [google-drive-export-plan.md](google-drive-export-plan.md) |
| Google OAuth | Standard sign-in and revocation | When the user connects or revokes | [google-drive-product-setup.md](google-drive-product-setup.md) |
| Open Food Facts | A barcode for an authorised lookup, or the displayed terms of a submitted search | Only when the online food database is enabled | [unified-food-search-contract-v1.md](unified-food-search-contract-v1.md), [off-barcode-candidate-plan-v1.md](off-barcode-candidate-plan-v1.md) |
| OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
| OpenRouter and its one allow-listed model endpoint (ZDR, data collection denied, no fallbacks) | One cropped, downscaled label photo re-encoded with all metadata removed, plus a fixed instruction and output schema; no name, brand, food log, health data or identifiers | Only when the user taps Read label with AI on the Label photo screen, with the user's own validated key; on the first tap of a session, and on the first tap of each new local day, two catalogue requests (the model's endpoint listing and the ZDR endpoint listing) with no key and no user data first confirm the endpoint; at most 3 attempts for retryable failures and $0.05 in total per tap; at most 30 reads and $0.50 per day, a cap shared with the pasted label text route once that route is enabled ([pasted-label-ai-text-v1.md](pasted-label-ai-text-v1.md) D14), which sends nothing until its own row is added here | [label-photo-ai-prefill-v1.md](label-photo-ai-prefill-v1.md) |
| A chosen public source page | An HTTPS page request (no key, no user data) | During an explicit web lookup | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |

## Rules for every egress path

- User-initiated and visible; no automatic retries, pagination, per-keystroke requests or background work beyond the approved budget for that path. A path's contract may approve bounded retries of retryable transport failures within the one user action, with backoff that honours `Retry-After` and a whole-call deadline (label photo reading: 3 attempts in 90 s).
- User-owned credentials live in this-device-only Keychain storage and are never sent to third-party publishers.
- Responses are evidence for review, never authority: citations or model confidence alone never authorise nutrition or saving.
- Adding a destination, widening a payload or changing when a request happens needs a versioned contract, an update to this file and `privacy-policy.txt`, and explicit user approval. Prove a new transport with synthetic data before integrating it with HealthKit or any other personal data.

## In force, route not yet enabled for users

- **Label photo reading through OpenRouter** (#316): the owner approved egress terms E1 to E16 on 25 October 2026 ([label-photo-ai-prefill-v1.md](label-photo-ai-prefill-v1.md) sections 10 and 17), and its section 11 row, retry amendment and on-device photo rule are in force above from the PR that wires the live transport (E16). The live route stays behind the `-LabelPhotoRoute live` launch argument, with no user-visible setting, until the E13 qualification passes and the owner's device check (section 17.21); until then a released build sends no label photo.

## Retired

Gemini is no longer used by the app. Its contracts remain in [`archive/`](archive/) as regression evidence only.
