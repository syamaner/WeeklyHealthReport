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

## 2. Results

Not yet run.
