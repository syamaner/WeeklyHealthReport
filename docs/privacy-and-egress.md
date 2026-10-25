# Privacy and data egress

This is the single engineering list of what may leave the device, where it goes and which contract governs it. The user-facing statement is [`privacy-policy.txt`](privacy-policy.txt); keep both consistent. Anything not listed here must not leave the device.

## Stays on the device unless the user sends it

- **HealthKit data** leaves only inside a Daily JSON export the user reviews and sends, or a report or Today screen the user copies, shares or screenshots (including the today-so-far Health values in Today's Full Page).
- **Notes** leave only inside the Daily JSON export for their day. Today's Full Page shows only today's note count, never note text.
- **The food log** for one selected day leaves only inside the separate food daily export file the user reviews and sends to Google Drive ([food-daily-export-contract-v1.md](food-daily-export-contract-v1.md)); the health Daily JSON export never contains it. Otherwise the food log, intake history, saved foods, favourites, drafts and inventory stay local, except an inventory backup file the user explicitly exports to a location they choose, and Today's Full Page when the user takes a screenshot and chooses Full Page: it contains today's food totals and quick-add favourite names and default amounts. The Health report's Copy all and Full Page contain the Food and water section's logged-day counts and averages ([health-food-and-water-v1.md](health-food-and-water-v1.md)). HealthKit food writes remain a separate plan (#97).
- **Audio** never leaves. Speech recognition is on-device only.

HealthKit access is read-only: authorisation `toShare` stays empty. No analytics, tracking, crash SDK, backend, account system or background delivery.

## Allowed egress

| Destination | What is sent | When | Contract |
|---|---|---|---|
| Clipboard, share sheet or the iOS screenshot editor | The report text, or a Full Page PDF of Health (the report) or Today (today's food totals, quick-add favourite names and amounts, today's note count and today-so-far Health values), created in memory; or a misread report for a pasted nutrition label (the pasted label text, the values read from it, and the parser, gate, check and conversion versions), as previewed and edited by the user | Only when the user chooses Copy all, Share, a screenshot's Full Page, or Report a misread, and then saves or shares it; the user picks the destination in the system share sheet and can cancel; the app has no destination of its own and nothing is sent automatically | [README.md](../README.md), [pasted-nutrition-label-v1.md](pasted-nutrition-label-v1.md) |
| A file location the user chooses | The inventory backup file | Only when the user chooses to export a backup | [food-library-storage-and-backup-decision.md](food-library-storage-and-backup-decision.md) |
| Google Drive (`drive.file`) | The exact reviewed Daily JSON bytes (health data, selected-source nutrition and that day's notes), and, when the user keeps Food log on, the exact reviewed food daily JSON bytes for the same day (log entries, nutrient values with their sources, daily totals), each with minimal export-identity metadata | Only when the user chooses Export | [daily-export-contract.md](daily-export-contract.md), [food-daily-export-contract-v1.md](food-daily-export-contract-v1.md), [google-drive-export-plan.md](google-drive-export-plan.md) |
| Google OAuth | Standard sign-in and revocation | When the user connects or revokes | [google-drive-product-setup.md](google-drive-product-setup.md) |
| Open Food Facts | A barcode for an authorised lookup, or the displayed terms of a submitted search | Only when the online food database is enabled | [unified-food-search-contract-v1.md](unified-food-search-contract-v1.md), [off-barcode-candidate-plan-v1.md](off-barcode-candidate-plan-v1.md) |
| OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
| A chosen public source page | An HTTPS page request (no key, no user data) | During an explicit web lookup | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |

## Rules for every egress path

- User-initiated and visible; no automatic retries, pagination, per-keystroke requests or background work beyond the approved budget for that path.
- User-owned credentials live in this-device-only Keychain storage and are never sent to third-party publishers.
- Responses are evidence for review, never authority: citations or model confidence alone never authorise nutrition or saving.
- Adding a destination, widening a payload or changing when a request happens needs a versioned contract, an update to this file and `privacy-policy.txt`, and explicit user approval. Prove a new transport with synthetic data before integrating it with HealthKit or any other personal data.

## Pending owner approval (not in force)

- **Label photo reading through OpenRouter** (#316): proposed row, retry amendment and on-device photo rule in [label-photo-ai-prefill-v1.md](label-photo-ai-prefill-v1.md) section 11. Until the owner approves its egress checklist (section 10) line by line, no label photo leaves the device and the current app sends none.

## Retired

Gemini is no longer used by the app. Its contracts remain in [`archive/`](archive/) as regression evidence only.
