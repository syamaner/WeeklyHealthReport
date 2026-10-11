# Privacy and data egress

This is the single engineering list of what may leave the device, where it goes and which contract governs it. The user-facing statement is [`privacy-policy.txt`](privacy-policy.txt); keep both consistent. Anything not listed here must not leave the device.

## Stays on the device unless the user sends it

- **HealthKit data** leaves only inside a Daily JSON export the user reviews and sends, or a report the user copies, shares or screenshots.
- **Notes** leave only inside the Daily JSON export for their day.
- **The food log,** intake history, saved foods, favourites, drafts and inventory stay local, except an inventory backup file the user explicitly exports to a location they choose. Food-log entries are not part of the Daily JSON export today: the shipping Drive coordinator rejects payloads that contain them. Adding them is a separate contract (#97).
- **Audio** never leaves. Speech recognition is on-device only.

HealthKit access is read-only: authorisation `toShare` stays empty. No analytics, tracking, crash SDK, backend, account system or background delivery.

## Allowed egress

| Destination | What is sent | When | Contract |
|---|---|---|---|
| Clipboard or share sheet | The report text or Full Page image | Only when the user chooses Copy all, Share or a screenshot | [README.md](../README.md) |
| A file location the user chooses | The inventory backup file | Only when the user chooses to export a backup | [food-library-storage-and-backup-decision.md](food-library-storage-and-backup-decision.md) |
| Google Drive (`drive.file`) | The exact reviewed Daily JSON bytes (health data, selected-source nutrition and that day's notes) and minimal export-identity metadata | Only when the user chooses Export | [daily-export-contract.md](daily-export-contract.md), [google-drive-export-plan.md](google-drive-export-plan.md) |
| Google OAuth | Standard sign-in and revocation | When the user connects or revokes | [google-drive-product-setup.md](google-drive-product-setup.md) |
| Open Food Facts | A barcode for an authorised lookup, or the displayed terms of a submitted search | Only when the online food database is enabled | [unified-food-search-contract-v1.md](unified-food-search-contract-v1.md), [off-barcode-candidate-plan-v1.md](off-barcode-candidate-plan-v1.md) |
| OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
| A chosen public source page | An HTTPS page request (no key, no user data) | During an explicit web lookup | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |

## Rules for every egress path

- User-initiated and visible; no automatic retries, pagination, per-keystroke requests or background work beyond the approved budget for that path.
- User-owned credentials live in this-device-only Keychain storage and are never sent to third-party publishers.
- Responses are evidence for review, never authority: citations or model confidence alone never authorise nutrition or saving.
- Adding a destination, widening a payload or changing when a request happens needs a versioned contract, an update to this file and `privacy-policy.txt`, and explicit user approval. Prove a new transport with synthetic data before integrating it with HealthKit or any other personal data.

## Retired

Gemini is no longer used by the app. Its contracts remain in [`archive/`](archive/) as regression evidence only.
