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

### Amendment 5 (owner, 7 November 2026, after the Amendment 4 recheck, before the text seal and before any reader run on fresh text)

The owner made four rulings in chat during the Amendment 4 recheck. No reader or parser had run on any fresh text when they were made. This commit records them:

1. **Where the recheck searched.** The agent ran the recheck searches for slots 21 to 23 in Claude in Chrome, in the owner's own profile (which may be signed in to Google), one results page per navigation. This replaces the owner's Safari search in Amendment 4 items 4.3 and 5 for those slots, and the results say so.
2. **Slot 21, positions 8 and 25.** Both showed the agent a block page. Neither was cleared, and both sites moved to the owner. The owner had no time to open them, so both were judged from their result titles, and V21 stands. This is the one place where the recheck judged a result without opening it.
3. **Slot 22, position 9.** The result failed to load twice (a timeout). It was judged from its title, as the nutrition index of an ice-cream parlour chain: a foodservice outlet, like the restaurant guides (`not_source_kind`).
4. **Slot 22, position 17.** The server sent this result as a download, so Chrome saved the PDF without it first being listed to the owner. The owner approved it afterwards from its name, site and size, and it was moved unopened into the private folder with its hash recorded. Opened in Preview, it shows a product for the school-meals market of another country with that country's panel, so it is skipped `non_uk` on the PDF's own evidence. V22 stands.

The recheck changed no label: 24 labels stand, with none withdrawn and no new IDs.

### Amendment 6 (owner, 7 November 2026, after blind transcription, before seal 1 and before any reader run on fresh text)

An independent read-only check compared the 24 transcriptions with their screenshots, without seeing the copied texts or any reader output. It passed 23. On the other, the only column heading names both a per 100 g and a per 100 ml basis, and the transcriber recorded one of them, chosen from the kind of product rather than from the table.

The transcription schema records a column's basis "as the heading states it", or `null` when the label states none. From this commit:

1. **A heading that names more than one basis records `null`.** A basis is recorded only when the label states one basis for that column. A heading that offers two is not one basis, and the product's kind, packaging or category does not choose between them. The note says which bases the heading names.
2. **Scored as recorded.** The scorer is unchanged. If the reader asks for the basis, the simulated choice is "not sure"; if the reader assumes one, that column has no printed match.
3. **One label is affected,** and it is re-transcribed by the blind transcriber before seal 1. The other 23 are unchanged.

## 2. Results

### 2.1 Run

- **Seals.** Text seal 7 November 2026, 11:42 UTC; seal 1 (blind transcriptions as handed over) 15:44 UTC; seal 2 (after the independent check and Amendment 6) 15:45 UTC. 24 files under each seal.
- **Transcription check.** An independent read-only check compared all 24 transcriptions with their screenshots, blind to the copied texts and to reader output. It passed 23, and the other is the one Amendment 6 covers.
- **Reader run.** One run, from a clean checkout of the freeze reference `21c3247`, attempt 1, with no rerun. Since that commit only documentation has changed. The run wrote 24 outputs, and scorer v2 scored all 24.

### 2.2 Bar and goals (harness)

| | Labels | Reached Confirm | Declined | Values checked | Wrong values | Tables with a wrong value |
|---|---|---|---|---|---|---|
| All | 24 | 5 | 19 | 87 | 0 | 0 |
| Tier A | 9 | 0 | 9 | 0 | 0 | 0 |
| Tier B | 15 | 5 | 10 | 87 | 0 | 0 |

- **The bar holds in the harness: zero wrong values** in every table that reached Confirm. Rule-of-three upper limits (95%), all labels: 0.034 per value and 0.600 per table. The per-table limit is wide because only 5 tables reached Confirm.
- **Decline rate (goal at most 25%, not gating):** 79% of all labels (19 of 24), 100% of tier A (9 of 9) and 67% of tier B (10 of 15). The goal is not met.
- **Correction burden (goal median at most 1, not gating):** mean 0.8, median 1, over the 5 tables that reached Confirm. Met. No basis choice was needed.
- **Other counts:** 0 rows printed but not read; 0 calculated-versus-printed discrepancies. All 24 were scored on the UK declaration panel.
- **Tier A** is the figure least dependent on the sites the rules were built on. None of its 9 labels reached Confirm, so its value and table limits rest on no tables. On new sites the bar holds because the reader declines, not because it reads.

### 2.3 Declines by reason

| Reason | All | Tier A | Tier B |
|---|---|---|---|
| `count_mismatch` | 7 | 4 | 3 |
| `value_without_unit` | 4 | 3 | 1 |
| `basis_state_not_supported` | 2 | 0 | 2 |
| `no_basis_header` | 2 | 0 | 2 |
| `duplicate_basis` | 1 | 0 | 1 |
| `layout_ambiguous` | 1 | 0 | 1 |
| `multiple_panels` | 1 | 1 | 0 |
| `uk_orphan_unit` | 1 | 1 | 0 |

### 2.4 By copy method and browser

| Copy method and browser | Labels | Reached Confirm | Declined | Values checked | Wrong |
|---|---|---|---|---|---|
| Scripted range, built-in browser | 15 | 3 | 12 | 67 | 0 |
| Scripted range, Claude in Chrome | 8 | 2 | 6 | 20 | 0 |
| Owner's rectangular Preview selection (PDF) | 1 | 0 | 1 | 0 | 0 |

Every rate here carries the copy-check caveat of P3 section 4.4: scripted copies add blank lines and a title line that Safari copies do not.

### 2.5 Set-aside counts by rule

87 entries: S2 45, S4 34, S7 6, S1 2.

### 2.6 Device step

Not yet run.
