# Food draft recovery and common foods

## Architecture and contracts

The application owns the versioned list checkpoint and its persistence capability.
Presentation saves input, edited row drafts, stable operation/evidence IDs, selection,
and saved/deferred/declined/context dispositions. The GRDB adapter owns atomic storage
and protected-data availability; the app composition root connects it to the ledger.
Search results and unaccepted confirmation screens are refreshed, not replayed as
accepted food. Ledger operations reconcile committed saves when a crash interrupts
the subsequent checkpoint. Identical retries use the existing food-list idempotency key.

Receipt review has a separate typed checkpoint capability and protected GRDB adapter.
It preserves pasted input, source selection, line corrections, selected rows and exact
pending save commands. A resumed uncertain command blocks editing until its identical
retry completes. Saved records and unsaved drafts stay distinct; restoring a compatible
inventory backup retains local draft corrections.

Inventory keeps its append-only product/source/review history. Common-food metadata
is optional on product versions; the database moves from schema 1 to 2 so an older
client cannot silently discard favourites and usual portions. Domain rules remain
independent of SwiftUI, GRDB, file pickers, and platform providers.

Inventory backup format 2 serialises the complete ordered command history and its
SHA-256 integrity hash. Restore validates every command and source hash before one
atomic transaction. Only identical prefixes can extend a local history. Repeated or
older compatible backups are harmless; divergent histories fail without overwriting
local reviews. A backup includes original receipt bytes and text, aliases, favourites,
usual portions, and historical corrections. It is not encrypted or anonymised.
It remains separate from the existing food-ledger archive and daily health export;
those schemas are unchanged. Unsaved drafts are local recovery state, not backup
members. File selection/export is user initiated from receipts or Common Foods.

Favourites are explicitly managed local names, aliases and optional usual portions.
Quick-add adds a line to the persistent review queue and opens it. It does not assert
food identity, nutrition, consumption, stock depletion, or a purchase. The existing
search and confirmation flow still requires the consumed amount and accepted match.
Receipt imports are optional and no Google connection is needed.

## Verification

Synthetic contracts cover reopening edited drafts with stable IDs and dispositions,
protected-data rejection, unsupported checkpoints, backup retry/prefix extension,
older-backup preservation, divergent history rejection, tampering and usual portions.
Presentation checks cover adding shortcuts to an existing queue, resuming status,
and recovering a save that committed before checkpoint completion.

Delivery validation: 148 package tests, 259 app simulator tests, Xcode static
analysis, target-boundary checks, 15 frozen-matching tests and frozen-report
verification passed. Backup contracts include original receipt bytes, review
history, favourites, idempotent restore, compatible extension and rejection of
tampering/divergence. Receipt retry also resumes across model reconstruction after
an uncertain committed save without duplicating records.

The autonomous review inspected five simulator renderings from synthetic hosted
tests: standard and accessibility-size common foods, saved receipt source,
unresolved list and resumed list. It added permanent name/amount labels, a shorter
intro, an inline common-food title and independent row buttons. This is rendered
screen and synthetic orchestration evidence, not an interactive file-picker or
physical speech/camera validation, nor personal HealthKit behaviour.
