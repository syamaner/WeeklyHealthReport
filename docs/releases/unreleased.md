# Unreleased changes since 0.3.0 (30)

Release notes to carry into the next TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here. The entries since build 29 moved to the [0.3.0 (30) record](internal-testflight-0.3.0-build30.md).

## Search

- **Exact cocoa matches first (#462).** When you search for a chocolate with a cocoa percentage, an online product that states exactly that percentage now appears in a section at the top of Search results, "Online products with 90% cocoa", instead of at the bottom. Products named "95% dark chocolate" or "dark chocolate 95%" now show their cocoa percentage instead of "Cocoa % not stated". Ranking and estimates are unchanged.

## Food entry

- **Estimates for Open Food Facts chocolate (#464).** When you log an Open Food Facts chocolate product (from search or a barcode), Confirm can now estimate the nutrients the product does not list, such as fibre, from a bundled reference row, as it already does for pasted dark chocolate labels. You confirm the cocoa % (suggested from the product name) and choose the row; the product's own values are never changed, and the entry shows "Partly estimated". Filling in food details keeps the estimate; changing the name, brand or a value, marking the product fortified or changing its type withdraws it. A barcode rescan brings back the product's own values only.

## Before installing

- **Back up or export your food log first (#464).** Once a food log holds an estimated Open Food Facts entry, the store moves to version 9, and builds before this one cannot open it.
