# UK English pasted label reader v2, P4: release check record

Issue #371, phase P4. This record holds the amendments made to the v2 fresh-set protocol ([`pasted-nutrition-label-uk-english-v2-p3.md`](pasted-nutrition-label-uk-english-v2-p3.md) section 4) and, once the run is scored, the results. It holds counts only: no label text, value, product name, address or hash.

The frozen reader, identity, policy, harness and scorer are those of P3 (merge commit `21c3247`). Nothing in this phase changes product code, the harness or the scorer.

## 1. Amendments

### Amendment 1 (owner, 6 November 2026, before any v2 fresh page is opened)

In the v1 fresh collection, Co-op's online shop showed a postcode form before any search or product page. It is not a login, a CAPTCHA or a bot check, so it was not `blocked`; the agent entered nothing, logged the visit `other` and treated Co-op as exhausted for that category. Co-op is tier A retailer 1 in v2, so the same handling would remove it from tier A in practice.

From this commit:

1. **One fixed postcode.** When Co-op's shop shows a postcode or delivery-area form before a search or product page, the agent enters the postcode of Co-op's head office in Manchester, `M60 0AG`, and nothing else. It is a public business address, not personal data, and it is fixed here, before any page is opened, so it cannot depend on what a label shows.
2. **Recorded.** The postcode and every visit that used it are recorded in `collectors.json` and the skip log in the private folder.
3. **Only Co-op.** A postcode, store or delivery-area form on any other site is handled as before: logged `other` with a one-line note, the retailer exhausted for that category, and the note listed to the owner before the text seal.
4. **Nothing else changes.** No account is created, no sign-in is made, and no other field is filled. A form that asks for more than a postcode is logged `other`.

### Amendment 2 (owner, 6 November 2026, during the retailer slots, before any Google page is opened)

`collectors.json` started Google with the owner in Safari, because Google showed the agent a traffic-verification page in v1. The owner has now asked the agent to run the Google searches itself. No Google search or result had been opened for v2 when this was decided, so the change cannot depend on any v2 result.

From this commit:

1. **Google starts with the agent** in the Claude desktop built-in browser, signed out, with the interface in English and the region set to the United Kingdom (`hl=en`, `gl=uk`). The query, the 30-result window and what counts as a result are unchanged.
2. **The block rule is unchanged.** The first CAPTCHA, bot check or traffic-verification page Google shows the agent is logged `blocked` (collector `agent`), is never bypassed, and moves Google to the owner in a Safari private window for the rest of collection.
3. **Recorded.** The change and any later switch are recorded in `collectors.json`.

### Amendment 3 (owner, 6 November 2026, during the retailer slots)

The owner wants to watch collection and be able to step in. Computer use can only see a browser, not click or type in it, so it cannot drive Safari. The owner chose Claude in Chrome, the browser extension that acts in the owner's own Chrome. The browser is the same for every remaining label, chosen before the next slot's pages are opened, so it cannot depend on what a label shows.

From this commit:

1. **The agent's browser** is Claude in Chrome from the first slot the collector starts after reading this amendment. Labels already saved keep their records and stay as collected in the built-in browser. Each `source.json` names the browser.
2. **The copy method is unchanged:** one DOM range from the first visible character of the nutrition section to the last, and `window.getSelection().toString()` saved as UTF-8, byte for byte (v1 Amendment 2 item 1). **Google searches stay in the built-in browser** (Amendment 2), because it is signed out and the owner's Chrome may not be; the agent opens each result in Chrome. No site is signed in to, and the agent never signs the owner out of anything.
3. **The block rule is unchanged.** On a CAPTCHA, bot check or traffic-verification page the agent stops, logs `blocked` (collector `agent`) and never clears it. The owner becomes that site's collector for the rest of collection.
4. **Reported.** The results count labels by browser beside the copy-method counts.

### Amendment 4 (owner, 7 November 2026, after collection, before the text seal and before any reader run on fresh text)

Collection filled all 24 slots. An independent read-only review of the private records (no browsing, no reader, parser or test run) found every saved text matching its recorded hash, none matching the excluded set, and the site cap held. It also found owner rulings made in chat that were never committed, and four slots whose first-eligible order is not shown by the records:

- slot 19: the walk resumed at result 21 of a list whose results 10 to 20 the skip log never records;
- slot 22: the 30-result window counted two video entries, which are not results;
- slots 21 to 23: results were judged from Google's results page without being opened, and one `non_uk` skip rests on the site's domain alone.

Nothing about any label's reader output is known: no reader or parser has run on a fresh text. From this commit:

1. **Rulings made during collection, recorded.**
   1. *Paid tiles.* Ocado tiles labelled "Featured" are paid placements and not results, like "Sponsored" (6 November, slot 13, before any Ocado result was opened).
   2. *Google retry.* About 12 hours after the slot 20 block, Google returned to the agent in the built-in browser (signed out, `hl=en`, `gl=uk`), paced to one results page per navigation, with the block rule unchanged (7 November, 07:39 UTC). Google blocked the agent again on slot 24's first page and went back to the owner.
   3. *Holland & Barrett.* The owner returned the site to the agent in Claude in Chrome, one page per navigation and no parallel fetches (7 November, 07:55 UTC). The parallel checks made just before the slot 14 block are void: no position or skip rests on them.
   4. *Slot 24's search.* At the owner's instruction, the agent ran slot 24's search in Claude in Chrome in the owner's own profile, which may be signed in to Google (7 November, 08:00 UTC). This departs from Amendment 2 item 1 for that one search, and the results say so.
   5. *Slot 24's PDF.* The owner approved the download from its file name and site; no size was shown before the download, and the size is recorded after it. The owner copied the nutrition section in Preview with a rectangular selection of the title and table. A plain range in reading order took allergen captions from outside the section, so the rectangle is the section as 12.2.4 item 2 defines it. The copy method is recorded as an owner's rectangular Preview selection.
2. **Category boundaries (owner).** These are fixed before any recheck page is opened. Each affected skip-log row gains a `ruled_reason` field, and its original reason stays.
   1. *Formula.* Toddler milk formula and follow-on formula are outside every category, with infant formula (`supplement`).
   2. *Drinks for young children.* Plant-based growing-up drinks are not milk and yoghurt (`wrong_category`).
   3. *Complete-meal drinks* are neither ready meals nor soft drinks (`wrong_category`).
   4. *Soup* is not a ready meal (`wrong_category`).
   5. *Prose nutrition.* Nutrition given only as prose is `no_nutrition_table`.
   6. *Policy documents.* A bottler's policy document is `not_source_kind`.

   No saved label changes under these rulings.
3. **Collection practices that stand as recorded:**
   - a retailer with no site search is exhausted;
   - a search that redirects to a category page uses that page's order;
   - a retailer exhausted for a category stays exhausted for later slots of that category;
   - Booths' product search is its online ordering site;
   - each tier's rotation pointer restarts after that tier's last supplier;
   - viewport screenshots are the evidence kept.
4. **Recheck, in slot order, by the agent in Claude in Chrome, one page per navigation.**
   1. *Slot 19.* Run Planet Organic's search again for the slot's term with its default sort, and open results 10 to 20 in order. Record whether results 1 to 9 and 21 match the logged order. The first eligible result among 10 to 20 fills the slot. If there is none, V19 stands.
   2. *Slot 21.* Open each logged result in order, one per navigation. A candidate PDF is listed to the owner before it is downloaded, as before. A `non_uk` skip needs evidence on the page or in the PDF itself, such as a stated market, a label format for another country, or only non-UK addresses with no UK distributor. The domain alone is not that evidence.
   3. *Slot 22.* The owner runs the query again in a Safari private window and saves the first 30 organic results in order, with video, image, shopping and "People also ask" blocks left out. The agent then opens that list as for slot 21.
   4. *Slot 23* is rechecked as slot 21, over its logged list.
5. **When a recheck changes a label.**
   - The slot's previous label is withdrawn. Its text and records move to `withdrawn/` in the private folder before the seal, and its ID is never reused.
   - The new label takes the next unused ID, V25 onwards.
   - Every later slot is then walked again from its first step under the same rules. Saved orders are reused where they exist, and a slot keeps its label when the walk reaches the same result.
   - Every recheck visit is logged with `recheck: "amendment 4"`.
   - Any Google search a recheck needs is the owner's, in a Safari private window.

## 2. Results

Not yet run.
