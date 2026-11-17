# Unreleased changes since 0.3.0 (30)

Release notes to carry into the next TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here. The entries since build 29 moved to the [0.3.0 (30) record](internal-testflight-0.3.0-build30.md).

## Search

- **Exact cocoa matches first (#462).** When you search for a chocolate with a cocoa percentage, an online product that states exactly that percentage now appears in a section at the top of Search results, "Online products with 90% cocoa", instead of at the bottom. Products named "95% dark chocolate" or "dark chocolate 95%" now show their cocoa percentage instead of "Cocoa % not stated". Ranking and estimates are unchanged.

## Food entry

- **Estimates for Open Food Facts chocolate (#464).** When you log an Open Food Facts chocolate product (from search or a barcode), Confirm can now estimate the nutrients the product does not list, such as fibre, from a bundled reference row, as it already does for pasted dark chocolate labels. You confirm the cocoa % (suggested from the product name) and choose the row; the product's own values are never changed, and the entry shows "Partly estimated". Filling in food details keeps the estimate; changing the name, brand or a value, marking the product fortified or changing its type withdraws it. A barcode rescan brings back the product's own values only.
- **Faster logging for packaged products (#470).** An Open Food Facts product no longer needs the full Food details form: tap "No, not fortified" or "Yes, fortified" under "Packaged product, eaten as sold" and Log. If you do open the form, a reason is only needed when you change something the product states; filling in blanks needs none, and packing medium has "As sold" and "Not applicable" choices. Logging the same food again from recent foods or a favourite keeps the food details you gave ("Food details from your last entry"), so such favourites can use quick add. Filling in details no longer clears an entered weight or portion size.
- **Open Food Facts values named as such.** An Open Food Facts product's values come from a crowd-sourced database and stay marked as estimates, but the Food Log and Recent foods now say "Open Food Facts estimate" instead of a bare "Estimate", and each value on the saved entry reads "· Open Food Facts estimate". "Estimate" still shows when something else makes the entry an estimate, such as an estimated weight.
- **More barcodes find their product.** Open Food Facts often lists a product's values only per serving (for example "per serving (100 g)"). Scanning such a product said it had insufficient nutrition; it now scales the serving's values to per 100 g, says so on Confirm ("scaled from a 30 g serving"), and keeps them marked as Open Food Facts estimates for you to check. When a product's pack size and its nutrition panel disagree (a drink sold in ml with values per 100 g), the panel's basis is used and Confirm says so. On 231 products already bought, matches rose from 187 to all 231. Values that could not be right for any food once scaled (a mistyped serving size) are still declined.

## Export

- **Glucose readings in the Daily JSON (#469).** The Export screen has a new Glucose readings switch, off by default. With it on, the health file carries each glucose reading Apple Health shows for that day, with its time and source, alongside the daily and hourly figures it already had. Readings can reach Apple Health some hours late, so export the day again to include them; gaps are never filled in. Developer tools shows each source's count, first and last reading time and most common interval, for comparing with Apple Health.

## Before installing

- **Back up or export your food log first (#464).** This build moves the food log to store version 9 the first time it opens it, and builds before this one cannot open it afterwards. Archives and exports stay at their earlier contract unless they hold an estimated Open Food Facts entry.
