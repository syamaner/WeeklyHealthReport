# Recipes per input type

Each recipe ends with an intake file (see `intake-format.md`) in `<workspace>/inbox/`. Copy the
original input into its own folder under `<workspace>/inbox/raw-<source_id>/` first, and leave the
owner's original where it was.

## First build from receipts (empty workspace)

Run once, in this order, from a workspace holding only `work/`, `out/` and `inbox/`:

1. `extract_items.py <folder of PDFs> <workspace>/work` (gate must pass; see below).
2. `build_unique.py <workspace>/work/purchase-lines.jsonl <workspace>/work`, then review
   `unique-non_food.csv` and the VAT-marked food it lists.
3. `prepare_families.py <workspace>/work <repo>/Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/cofid-2021-generic-search-v1.json`
   writes `families.json`, the CoFID name index and four `mapping-batch-N.txt` files.
4. Map each batch with an offline subagent (the receipt form at the end of `mapping-prompt.md`, writing
   `work/mapping-N.json`), then `validate_mappings.py`.
5. `fetch_off.py <workspace>/work` (background, paced) to find label candidates.
6. `build.py <workspace> <repo>`: the first assembly records which candidates were chosen.
7. `fetch_off_products.py <workspace>/work <workspace>/out/personal-food-catalogue.json`
   (background, paced) fetches the full product record for each chosen candidate.
8. `build.py <workspace> <repo>` again: label values now come from those records.

Later receipts never re-run steps 1 to 3 (that would renumber families): use the recipe below.

## Receipt or invoice PDF (after the first build)

1. Run `extract_items.py <folder of PDFs> <workspace>/work/new-<date>`. It reads text in memory
   and writes only item fields. If the gate fails, read only the reported rule and line numbers,
   decide whether it is a false positive (a brand such as "Mr Kipling"), and add an exact
   exception; never loosen a rule.
2. A layout it does not recognise is reported as `unknown`. Add a parser branch for it, keyed by a
   marker string, and re-run; never guess at an unrecognised layout.
3. Check `coverage.json`: every document accounted for, wrapped names rejoined, nothing unclaimed.
4. `receipts_to_intake.py <workspace> <new>/purchase-lines.jsonl receipts-<date> <workspace>/inbox/receipts-<date>.json`.
   Read the resulting titles once for non-food that slipped through.

Scanned or image-only PDFs have no text: treat their pages as receipt photos.

## CSV or spreadsheet export

1. Read the header row only (`head -1`) to find the product, brand and pack columns. Never read
   data rows yourself: they may hold names, addresses or emails, and what you read reaches the
   model provider.
2. Extract only those columns with a short inline script into the intake file, dedupe titles, and
   run `intake.py add`, whose deny-list gate checks the result.
3. A stock sheet like the owner's "how much is left" file contributes titles and brands only.

## Free text (notes, pasted lists, chat)

1. Read the text and list each distinct food with any brand, variety, state and region it states.
   Do not copy amounts or times. Keep the owner's spelling in `aliases` when it differs ("haas
   avacado").
2. When the text names a food ambiguously (橄欖菜 written as "fresh leafy green"), keep it, put
   the doubt in `note`, and ask the owner rather than choosing.
3. Typed label numbers in the text become `label.origin = owner_typed` with their stated basis.

## App daily exports (food-daily, health-daily JSON)

Note text is read by the agent and so reaches the model provider; do this only when the owner
asks for it, as they did on 7 November 2026.

1. Ask the owner to download the files locally (the Drive connector would push whole files into
   context). Then `extract_exports.py <exports folder> <workspace>/work --print-notes`: it saves only
   the logged food names, and prints the note text for you to read once. Note text is never written
   to a work file.
2. Notes are free text: follow that recipe for the foods in them, writing an intake file.
3. `match_inputs.py <workspace>/work <workspace>/out/personal-food-catalogue.json` then lists what
   is already covered, for both the intake items and the logged entries. Logged entries are usually
   generic records already in the app: they need at most an alias, not a new entry.

## Label photo

1. Read the nutrition table. Use the per 100 g (or per 100 ml) column only; record the serving
   size in `serving` but do not convert.
2. Copy printed values exactly. Convert salt to sodium (g × 400 = mg) and kJ to kcal (÷ 4.184, only
   when kcal is not printed) and record each as a `transforms` entry with the printed value.
   `<0.5 g` style values are not exact: leave them out.
3. Set `origin: photo_unconfirmed`. Show the owner the values in a small table and ask them to
   confirm; on confirmation, edit the intake file to `photo_confirmed` and re-add it.
4. Read nothing else from the photo: no receipt, address or barcode beyond the product.

## Receipt photo

Transcribe product lines only, never the header, footer, payment or loyalty sections, into a
temporary list, then follow the free-text recipe. Do not keep the transcription.

## Product page (URL)

Fetch only pages the owner names, once, with the WebFetch tool. Record per 100 g
values as `page_unconfirmed`, with the URL in `note`. Ask the owner to confirm as for photos.

## Typed by the owner

The owner gives a title and, optionally, label values: write them directly with
`origin: owner_typed`.
