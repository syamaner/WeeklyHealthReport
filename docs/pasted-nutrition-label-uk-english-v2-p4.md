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

## 2. Results

Not yet run.
