# UX revamp v1 wireframes

Status: **agreed design baseline, 11 October 2026. Implementation not started.**

These are the source files of the 12 linked phone wireframes agreed for the UX revamp. They supersede the September food-log bundle in `docs/designs/food-log-all-screens.html` and the 26 September 12-screen bundle as the navigation and visual baseline. Specification, contract changes and the architecture gate: #193. Programme: #140.

Interactive canvas (private to the repository owner): https://claude.ai/artifact/R55ucfzmHiHpMgEcJQ3rBP

All values, product names and source sites in the screens are invented placeholders. The wireframes are design input; they do not authorise providers, data semantics or capabilities on their own.

## Screens

| File | Screen | Phase issue |
|---|---|---|
| `Main.dc.html` | Home: today's food, Add food, quick add, health today so far, notes | #199 |
| `AddFood.dc.html` | Add food: one search field, barcode, paste or dictate, favourites, recent | #196 |
| `SearchResults.dc.html` | Results with detected amount and preparation, progress with Stop, web lookup fallback | #196 |
| `WebLookup.dc.html` | One suggested source, match type, quoted text, "Use this source" | #196 |
| `Confirm.dc.html` | Food, inline blocking decision, amount, When, nutrition, source, one Log action | #195 |
| `QuickAdd.dc.html` | Quick-add sheet for water and favourites | #198 |
| `FoodLog.dc.html` | Day navigation, totals strip, entries by time, removed entries | #197 |
| `EntryDetail.dc.html` | Saved entry view with Edit and Remove | #197 |
| `Favourites.dc.html` | Quick-add order, other favourites, create from search, barcode or web | #198 |
| `Health.dc.html` | Period summary, grouped sections, Copy all; Full Page via the iOS screenshot buttons | #200 |
| `Export.dc.html` | Day, included preview, one Export action, verified result | #200 |
| `Settings.dc.html` | Food search, export, data, Apple Health, about and developer tools | #194 |

`canvas.json` records the canvas layout. The `.dc.html` files are Design Component pages that render inside the canvas runtime; open the canvas link above to view and click through them.

## Decisions captured in the screens

- Hub-and-spoke navigation from Home, no tab bar; Settings behind a gear button.
- Web lookup is an explicit fallback under "Not what you ate?"; online database enrichment stays automatic when enabled.
- Confirm has one Log action; blocking decisions appear inline only when needed; source identifiers sit behind details.
- Label and food photos are shown as "Not yet available".
- Full Page capture is triggered by the iOS screenshot buttons on the Health screen, with every section expanded.
