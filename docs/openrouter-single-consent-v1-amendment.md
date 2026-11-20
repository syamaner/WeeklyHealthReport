# One OpenRouter consent in Settings, explained in Privacy (O1)

Status: **proposed, 20 November 2026; decisions O1-D1 to O1-D3 made as recommended the same day;
the amendment as a whole is not yet approved, and there is no code.** Architecture gate PASS at round
eight (section 8). Written for #551 against `main` at
`91fa7479`. Nothing in this document changes app behaviour, [privacy and egress](privacy-and-egress.md)
or the bundled [privacy policy](privacy-policy.txt) until the owner approves the exact terms of
section 2 and the decisions of section 7. On approval, the amended documents of section 3 change in
the same PR that changes the app, so the records and the app never disagree (as label photo E16 did
for its transport).

It is a delta on [label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) (sections 4.1, 7.1, 7.2, 9,
10 (E4, E7, E8), 12 and 17.22), [generic food proposal integration v1](generic-food-proposal-integration-v1.md)
(architecture gate, presentation), [pasted label AI text v1](pasted-label-ai-text-v1.md) (product route
term T8, never approved and closed by D38), [AI search by name v1](ai-name-search-v1-proposal.md)
(A8, approved, not wired), [privacy and egress](privacy-and-egress.md) and the
[privacy policy](privacy-policy.txt). It repeats none of them, and everything they say that this
document does not name stays as written. On acceptance each amended document gains a dated note
pointing here.

## 1. Why

OpenRouter sits behind two routes in the app today, each with its own copy and its own approval:

- **Web lookup** (`GenericFoodProposalReviewView.swift`, `OpenRouterFoodKeyView`): no stored consent
  at all. It is gated only by a key validated in the current session and the explicit Look up action.
  The key screen carries four paragraphs of privacy and charges prose, and the review screen ends
  with an inline note on what is sent.
- **Read label with AI** (`LabelPhotoText.swift`, `LabelPhotoScreenModel.swift`): a Settings switch,
  "Read label photos with AI" (`labelPhoto.liveRoute.enabled.v1`, 17.22), an egress statement above the
  button on every read, a first-use sheet ("Send label photos to OpenRouter?") stored under
  `labelPhoto.egressConsent.live.v1` (and `labelPhoto.egressConsent.scripted.v1` for the Debug fake),
  a usage line under the button, and the Nutrition label entry's photo footer.

Two more approved or proposed routes (AI search by name, A8; Confirm enrichment, #549) would each add
another set, and the pasted label text route (closed) specified one too. So the same provider is
approved more than once, the same facts are repeated in slightly different words on every screen,
and the food journeys carry privacy prose at the point where the owner just wants to log food. That
conflicts with the assistive principle (AI pre-fills, the owner checks and corrects) and with the UX
rule "show a rule where it blocks saving; put the rest behind details".

This amendment gives OpenRouter one consent, in one place, and one written explanation, without
changing any destination or payload.

## 2. What changes

### O1.1 Settings › OpenRouter (one section)

A new Settings section, **OpenRouter**, directly after Food search. It holds everything about the
provider, and nothing about OpenRouter remains in Food search.

| Row | Kind | Copy | Notes |
|---|---|---|---|
| Consent switch | toggle | Title `Use OpenRouter for food lookups and label reading`; caption `Off by default. While it is off, the app sends nothing to OpenRouter. Uses your own key and credit.` | Native `Toggle`, title as its VoiceOver label, 44 pt |
| API key | link to the key screen | `API key`, detail as today's `webLookupDetail` (`Key added`, `Revalidate key`, `Key missing`, `Key not read yet`) | Replaces Food search's "Web lookup" row |
| Today's label reads | value row, shown only while the switch is on and a key is saved (when the live photo route can be reached) | `Label photo reads today`, detail `<n> of 30` | Only under decision O1-D1. Reads the live spend ledger file (`label-photo-spend-live-v1.json`, through the shared day record `label-ai-spend-day-v1`) directly: it creates no read session or flow and sends nothing. An unreadable ledger shows `Not available` |
| How the app uses OpenRouter | link | `How the app uses OpenRouter` | Opens the Privacy policy screen at its OpenRouter section (O1.3) |
| Footer link | external link | `Manage OpenRouter keys and limits` | `https://openrouter.ai/settings/keys`, as the key screen links today |

- **The switch.** A Boolean in the root's `UserDefaults` under a new, versioned key,
  `openRouter.consent.v1`, read and written only through one `OpenRouterConsentPreference` (the shape
  of `LabelPhotoReadingPreference` today). A missing or non-Boolean value reads as off; turning it off
  removes the value. No record, archive or export carries it.
- **Turning it off stops every OpenRouter request at once** (O1.2). It does not delete or invalidate
  the key: the key stays in the Keychain until the owner taps Remove key, and a session's validation
  survives a switch that is turned off and on again.
- **The key screen.** `OpenRouterFoodKeyView` keeps its API key section (paste, Save and validate key,
  Revalidate saved key, Remove key, the key message), unchanged while the switch is on; with the switch
  off its button and message change as decision O1-D2 says and its two links (OpenRouter
  privacy, Manage OpenRouter keys and limits). Its "Privacy and charges" prose moves to the privacy
  policy (O1.3) and is replaced by one line, `Your key stays in this device's Keychain.`, and a link
  `How the app uses OpenRouter` that opens the Privacy policy screen at its OpenRouter section, as the
  Settings row does. Its title stays `OpenRouter API key`.
- **Food search after the change.** Rows: Online food database, Food market. The "Web lookup" row and
  the "Read label photos with AI" toggle move out (the toggle is replaced by the consent switch under
  decision O1-D3). The footer returns to Open Food Facts only:
  `Open Food Facts receives only the food terms you search for or a barcode you look up. Your Health
  data and food log stay on this device unless you export them to Google Drive.`

### O1.2 What the switch gates (every route, closed)

**While the switch is off, the app sends no request to any OpenRouter host, on any route, for any
reason.** That covers:

1. Web lookup: discovery, source and lead selection, extraction, the applicability check and optional
   Jev selection (`OpenRouterFoodProvider`).
2. Key validation (`OpenRouterFoodProvider.validate`, called from `FoodWebDiscoveryViewModel`), under
   decision O1-D2.
3. Label photo reading: the read (`OpenRouterTransport` through `OpenRouterLabelPhotoAttempt`) and its
   keyless catalogue checks (`OpenRouterLabelRouteChecker`, E7).
4. The pasted label text adapters that exist in code but are not wired into the app
   (`OpenRouterPastedLabelAITextAttempt`, `OpenRouterPastedLabelAITextRouteChecker`): they take the
   gate now, under uses that are not in force, so the app's gate always refuses them (section 6).
5. Any later route (AI search by name, Confirm enrichment of #549, a reopened pasted label route): it
   takes the same gate before it may send, and its own contract cannot replace the gate with a
   per-feature approval.

Page fetches from public publishers (web lookup's chosen source, fetched through the reviewer's
`FoodDocumentCapturing`, which the app builds as `PublicFoodSourceCapture`) are not
OpenRouter requests, but they happen only inside a web lookup. The web lookup orchestration
(`GenericFoodProposalReviewer`) asks the gate, as `webLookup`, immediately before each `capture.capture` call as well as
before each model call, so with a supplied address, or after the switch goes off mid-lookup, no page is
fetched.

**Enforced twice.**
- **In presentation.** Each journey checks the switch and the key before it offers its send action,
  and shows the blocked row of O1.4 instead.
- **At the request site.** One consumer-owned gate, `OpenRouterEgressPermitting` (section 6), is asked
  immediately before every send, including each retry attempt (after any backoff wait, so a switch
  turned off during the wait stops the next send), at these sites:
  `OpenRouterFoodProvider.request` (as `keyValidation` for `v1/key`, as `webLookup` for every other
  path), the web lookup orchestration before each `capture.capture` (`webLookup`),
  `OpenRouterLabelPhotoAttempt.attempt` before `transport.send` (`labelPhotoRead`),
  `OpenRouterLabelRouteChecker`'s two catalogue fetches, and the two pasted label text adapters
  (`pastedLabelTextRead`). The catalogue fetch takes its use from the caller
  (`fetch(_:use:)`): the photo checker's `check()` passes `labelPhotoCatalogueCheck`, and
  `OpenRouterPastedLabelAITextRouteChecker`, which calls the photo checker's `fetch` directly, passes
  `pastedLabelTextCatalogueCheck`, so the app's gate refuses it. `OpenRouterTransport` and `ScriptedLabelPhotoTransport` do not change: a transport sees
  only URLs and cannot tell one use from another, and the scripted one sends nothing.
- **A refusal is its own outcome, never a key or route failure.** It surfaces as the O1.4 blocked row
  (switch off), with no change to key or route state:
  - web lookup and key validation: a new `FoodWebDiscoveryError.notPermitted`, which never calls
    `credentials.reject`, never clears `keyIsUsable` and never shows rejected-key text. In
    `GenericFoodProposalReviewer` it is rethrown, unwrapped, at every site that rethrows
    `.credentialRejected` today (source selection, extraction and the applicability check), and it is
    never turned into a `GenericFoodProposalPartialFailure`, a `selectionFailure` (which would return a
    usable review with ranking unavailable) or an `.acquisition(.invalidResponse)`. Both web lookup view
    models (`FoodWebDiscoveryViewModel` and `GenericFoodProposalReviewViewModel`) receive the gate and
    map `.notPermitted` to the blocked row, never to "The source review did not complete its checks". The orchestration's
    check before `capture.capture` runs outside the capture `do`/`catch`, so a refusal never reaches the
    second-lead retry;
  - key validation: `FoodWebDiscoveryViewModel.validate(key:saveNewKey:)` asks the gate first, before
    `invalidateUsability()`, so Revalidate with the switch off keeps the session's validation;
    `message(for:)` gains a `notPermitted` case with the O1.4 switch-off sentence;
  - label photo read: the attempt returns `.notSent(.notPermitted)`, a new case of
    `LabelImageReadingFailure`. When the session ends a tap on a `.notSent(.notPermitted)` attempt with
    sent attempts already recorded, it returns a second new case, `.notPermittedAfterSending`, so the
    screen can tell the two apart (`progress` alone cannot, since it fires before the first attempt);
  - catalogue check: a new `LabelPhotoRouteCheckFailure.notPermitted`, which `LabelPhotoReadSession`
    returns as `.failed(.notPermitted)` without setting `routeUnavailableOn`, so switching off, tapping
    and switching on again leaves the route available the same day.
  - the composition root's read closure, which today returns `.failed(.routeUnavailable)` when
    `stillInForce()` fails, decides with `OpenRouterAccess.blockedReason(consentOn:keyState:)`: switch
    off gives `.failed(.notPermitted)` (the switch-off row), and a removed key with the switch on gives
    `.failed(.keyMissing)` (an existing case), which `LabelPhotoText` maps to the O1.4 no-key row; neither
    shows route-unavailable copy or "Turn on OpenRouter" for the wrong reason.
  - pasted label text (not wired): the attempt returns `.notSent(.notPermitted)`, a new case
    `notPermitted = "not_permitted"` of `PastedLabelAITextNotSent`, rather than `requestRefused`, which
    would mislabel it; the route checker throws a new `CheckError.notPermitted`. The shared contract
    suite `PastedLabelAITextPortContracts` (contract test 28) gains the case, so the fakes and the real
    adapters agree.
  - **The label photo read closure's key state** comes from the same source as the screen environment
    for that mode: in a scripted mode the `-LabelPhotoKey` argument (today's `keyState` closure), in
    live mode the shared `FoodWebDiscoveryViewModel`; never a fresh Keychain read. A not-validated key
    passes the closure as today (the screen's `keyNotValidated` blocker, now the O1.4 row, already
    stops the tap before the closure runs), so the closure
    refuses only for switch off and a missing key.
  `LabelImageReadingFailure`, `LabelPhotoRouteCheckFailure` and `FoodWebDiscoveryError` are not
  `Codable`. `PastedLabelAITextNotSent` is `Codable` with raw values, but it is in no app record,
  archive or export (the route is not wired); the new raw value is additive, and the pasted label
  evaluation tool passes a gate that permits its uses, so its private records never contain the case. So no format
  changes.
- **The daily count.** `LabelPhotoReadSession` asks the gate before the catalogue check (as
  `labelPhotoCatalogueCheck`) and before it reserves the tap (as `labelPhotoRead`); a refusal there reserves nothing and is not counted towards the 30 reads. A
  refusal at the attempt, after the reservation (the switch turned off in the narrow window between
  the two), is a `.notSent` attempt, which the session already handles: it adds no attempt, so a
  refusal of the first attempt releases the reservation (`LabelPhotoSpendPolicy.released`) and the tap
  is not counted, and a refusal of a retry settles the tap on the attempts already sent
  (`LabelPhotoSpendPolicy.reconciled`). E10 and its settlement do not change. Because an attempt was
  already sent in that second case (`.notPermittedAfterSending`), `LabelPhotoText` maps it to the
  existing `Stopped. The photo may already have reached OpenRouter; nothing was saved.` above the
  blocked row,
  so a failure that may have sent data still says so; a refusal with no attempt sent shows the
  blocked row alone.
- A request already on the wire is not recalled; Cancel stops what follows, as today.

**Label photo route visibility (decision O1-D3).** The route mode resolves from the consent switch in
place of `labelPhoto.liveRoute.enabled.v1`; every other row of the 17.22 matrix stands:

| Build | `-LabelPhotoRoute` | Consent switch | Key saved | Mode |
|---|---|---|---|---|
| Debug | a scripted scenario | any | any | that fake scenario; with the switch off it shows the blocked row and reads nothing (the scripted flow's gate is the same preference) |
| Debug | `live` | any | any | live; with the switch off it shows the blocked row and the adapter gate refuses |
| Debug | any other value | any | any | off |
| Debug or Release | absent | off | any | **off** (the default; the route is hidden as today) |
| Debug or Release | absent | on | no | off |
| Debug or Release | absent | on | yes | live |
| Release | anything | as above | as above | the argument is ignored |

The internal-TestFlight-only rule of 17.22 and `privacy-and-egress.md` is unchanged: a build that can
reach the live photo route is exported only with `Config/ExportOptions-internal-testflight.plist`.

**Where consent is read, and how tests seed it.** `UserDefaults` also reads launch arguments, so
`-openRouter.consent.v1 YES` would read as consent through the argument domain. The preference
therefore reads the app's persistent domain only (`UserDefaults.persistentDomain(forName:)` for the
app's bundle identifier, or the injected suite in tests), never the argument domain, in every build.
Simulator journey checks seed consent with a launch argument, `-OpenRouterConsent on|off`, resolved by
one pure function, `OpenRouterConsentSeed.resolve(argument:debugBuild:)`, in the shape of
`LabelPhotoRouteMode.resolve`: in a Debug build `on` writes the persistent value and `off` removes it,
before the first scene; any other value, and every value in a Release build, does nothing. Because
the value persists, a check of the blocked row passes `off` rather than omitting the argument. (The
project has no UI test target today; these arguments serve `journey-qa` runs and any later UI tests.)

### O1.3 One Privacy section (privacy policy, amended)

The bundled privacy policy gains one **OpenRouter** section, and the OpenRouter sentences now spread
over "Optional online food search" (its web nutrition paragraphs, the label photo paragraph and the
key and retention paragraph) move into it, reworded only to fit one list. Open Food Facts stays in
"Optional online food search". The Privacy policy screen (`PrivacyPolicyView`, which reads the bundled
`docs/privacy-policy.txt` into one `Text` today) splits the text into sections at its heading lines (a
non-empty line that contains no full stop and no colon, is preceded by a blank line or the start of the
file, and is followed by a blank line), renders each as its own
view with the heading as its identifier, and, when reached from Settings › OpenRouter, scrolls to the
section whose heading is `OpenRouter` with a `ScrollViewReader`. The text itself is unchanged by the
split; Dynamic Type and text selection behave as today. The lines before the first blank
line (the title and the `Effective <date>` line) are the title block, shown above the first section
and never matched as a heading; a test pins the title block and the exact list of headings produced
from the bundled file.

The section lists every OpenRouter use the build can make, and for each: when it happens, what it
sends, what it never sends and its limits. The exact text is in section 3.5. It is the single
user-facing source; `privacy-and-egress.md` stays the engineering list, and a contract test checks
that the two name the same uses (O1.6, test 6).

**Room for later uses, approving none of them.** The section ends with `Other uses are added to this
list only in the release that starts them, after their own approval.` A later contract (#549's Confirm
enrichment, AI search by name P4) adds its own entry, in the same shape, in the PR that wires it. This
amendment does not list, describe or approve any of them, and the switch's caption names only the
uses in force; a later route that changes the caption's scope changes it in its own contract.

### O1.4 Quieter journeys

**Copy rule for journeys.** A line stays only when it changes what the owner does next: check an
AI-read value, notice an estimate, fix a blocked step, or know that something may already have been
sent. A line that states the obvious, repeats what Settings and Privacy explain, or adds a step with
no gain is removed.

**Removed.**

| Where | Element | Source |
|---|---|---|
| Label photo screen | Egress statement above the button | `LabelPhotoText.egressStatement` (7.1) |
| Label photo screen | First-use sheet: title, body, `Send photo`, `Not now`, `Privacy policy` link | `LabelPhotoText.firstUse*`, `LabelPhotoScreenModel.firstUseAccepted` (7.1, E4) |
| Label photo screen | Under-button line `Uses your OpenRouter key and credit. Today: <n> of 30 reads.` | `LabelPhotoText.underButton(reads:)`; moves to Settings under O1-D1 |
| Nutrition label entry | Photo footer `Taiwan labels only. The part you crop is sent to OpenRouter to be read. Nothing else is sent.` | `NutritionLabelEntryText.photoFooter`; replaced by `Taiwan labels only.` |
| Web lookup review | Closing inline note on what is sent to OpenRouter | `GenericFoodProposalReviewView.swift` (the last `Section` of the review) |
| Key screen | "Privacy and charges" paragraphs | `OpenRouterFoodKeyView`; moved to the policy (O1.1) |

**Kept as they are.** The Add food row subtitles (`Read by AI; you check every value.` and
`NutritionLabelEntryText.addFoodRowSubtitlePhotos`), the "Read by AI from your photo" check note on
Confirm, every reading, retrying, declined and failed state of 7.2 and of web lookup, including
`Stopped. The photo may already have reached OpenRouter; nothing was saved.`, the daily limit and
paused blockers, offline and route-unavailable, the estimate tags, and the stored provenance on food
records. Their wording does not change in this amendment except where it names a Settings location
that moves (below).

**One compact blocked row.** Where a journey cannot send because of consent or the key, it shows one
row in place of its send action, with one link to Settings › OpenRouter. The reasons are closed and
checked in this order:

| Reason | Copy | Link |
|---|---|---|
| Switch off | `Turn on OpenRouter in Settings to use this.` | `OpenRouter settings` |
| No key saved | `Add your OpenRouter key in Settings.` | `OpenRouter settings` |
| Key not validated this session | `Validate your OpenRouter key in Settings.` | `OpenRouter settings` |

- **Label photo.** The row replaces the blockers `turnedOff`, `noKey` and `keyNotValidated` and their
  buttons (`OpenRouter settings`, `Validate key`), with the same `labelPhoto.blocker` identifier; the
  other blockers stay as they are. Read label with AI stays disabled while the row shows.
- **Web lookup.** The row replaces `Web lookup needs your OpenRouter key.` with its `Add or validate
  key` button, and the pre-send message `Add or revalidate your OpenRouter key first.`
- **Settings locations in failure copy.** Every key-rejected string that tells the owner where to act
  says Settings, in one sentence: `OpenRouter rejected the API key. Replace or revalidate it in
  Settings.` That is `LabelPhotoText.failedKeyRejected`, web lookup's `OpenRouter rejected this key. Add
  or revalidate a key.` (`GenericFoodProposalReviewView.swift`) and `FoodWebDiscoveryViewModel`'s
  `credentialRejected` message (shown on the key screen itself, so it keeps `Replace or revalidate it.`
  without "in Settings"). `FoodSearchStatusPresentation`'s `Revalidate it in Settings.` already names
  Settings and stays. No other failure string changes.
- The row is not a warning about egress; it is the place the action is blocked, as the UX rules ask.

### O1.5 Migration: no earlier consent becomes the new one

- `openRouter.consent.v1` starts absent, so the switch is **off for everyone after the update**,
  whatever was set before. The owner turns it on once.
- **Never read for consent:** `labelPhoto.egressConsent.live.v1`, `labelPhoto.egressConsent.scripted.v1`
  and `labelPhoto.liveRoute.enabled.v1`. A test sets each, alone and together, with a validated key,
  and proves the switch still reads off and no route sends.
- **Left in place, not deleted.** The new build neither reads nor writes these three keys, so a
  rollback to an older build finds them as it left them. They are listed in a code comment beside the
  new preference as retired, so no later change reuses the names.
- **Web lookup behaviour changes on update.** Today it needs only a validated key; after the update it
  also needs the switch. The blocked row says so. This is the intended effect, and is listed in the
  release notes of the build that carries it.
- The spend ledgers (`label-photo-spend-live-v1.json`, `label-photo-spend-v1.json`) and the shared day
  record `label-ai-spend-day-v1` are unchanged; today's count carries on across the update.

### O1.6 Contract tests (written first, synthetic data only)

1. **Switch off sends nothing, per use.** One test per `OpenRouterUse` case, kept complete by an
   exhaustive `switch` over the enum (adding a case does not compile until its test exists). A
   recording gate captures the use each request site passes; the pasted text checker passes
   `pastedLabelTextCatalogueCheck`, never the photo use, and the app's preference refuses it even with
   the switch on. With the
   gate refusing: web lookup by search and by supplied address (page fetch included), key validation,
   the label photo attempt (every retry) and both catalogue fetches, and the two pasted label text
   adapters each reach the recording transport or the recording `FoodDocumentCapturing` zero times
   (search, supplied address and the second-lead path, with no `GenericFoodProposalPartialFailure`), and each returns the
   outcome of O1.2. The presentation shows the blocked row.
2. **A refusal is not a rejected key or a broken route.** After a refusal the session's validation is
   kept, `reject` is never called and no rejected-key text appears, including Revalidate with the
   switch off (`keyIsUsable` unchanged); for web lookup, a refusal at each of discovery, source
   selection, capture, extraction and the applicability check reaches the caller as `.notPermitted`,
   unwrapped, with no review returned; for label photo, switch off, tap, switch on, and a read the same
   day succeeds (`routeUnavailableOn` unset); the spend ledger is unchanged after a refusal before
   reservation, the reservation is released after a refusal of the first attempt, and only the sent
   attempts are reconciled after a refusal of a retry, with the "may already have reached OpenRouter"
   line shown; the read closure's switch-off refusal shows the blocked row; switch on with the key removed, the
   read closure gives `.keyMissing` and the no-key row, never route-unavailable copy, and sends
   nothing; a refusal on attempt 2 of a retried web lookup request (refused after the backoff
   wait) ends with exactly one send and exactly one backoff wait, `.notPermitted`, no wait or send after
   the refusal and no `FoodProposalSelectionFailure`, and the same shape holds for a refused label
   photo retry; saving a new key with the switch off clears the session's `validatedKey` and
   `keyIsUsable` and bumps the credential generation, so after the switch is turned on no request
   carries the old key; the pasted text route checker with
   a refusing gate makes zero transport calls on both internal fetches and records
   `pastedLabelTextCatalogueCheck`; both pasted label text adapters return the new named cases and
   `not_permitted` round-trips; with `-LabelPhotoRoute <scenario>`, the switch on and no real Keychain
   key, a scripted read succeeds, and with the switch off it gives `.failed(.notPermitted)`; a live
   not-validated key at the read closure passes through and the screen's row blocks the tap; the web
   lookup review view
   model shows the blocked row for `.notPermitted`, with no partial or "did not complete" copy.
3. **Switch on changes nothing else.** With the switch on, each route's request bytes equal committed
   golden fixtures captured from `main` before the change (`OpenRouterLabelPhotoRequest`'s existing
   golden, and new goldens of web lookup's request bodies and headers, key removed).
4. **Turning off mid-journey.** Off while a label photo screen or web lookup is open: the next tap
   shows the blocked row; a retry attempt after the switch goes off is refused at the request site; a
   web lookup whose switch flips before `capture.capture` fetches no page and sends no model request.
5. **Migration and seeding.** Each retired key, alone and in every combination, with and without a
   key: the switch reads off; turning the switch on and off never writes or removes a retired key; a
   `-openRouter.consent.v1 YES` argument-domain value reads as off; `OpenRouterConsentSeed.resolve`
   writes for `on` and removes for `off` with `debugBuild` true, and does nothing for either with
   `debugBuild` false or for any other value.
6. **Boundary check.** `check-boundaries.sh` fails when a Swift file under `Packages/FoodLedgerKit/Sources`
   or `WeeklyHealthReport/` that builds or sends an OpenRouter request (it contains an
   `https://openrouter.ai/api` URL, or is one of the six request sites of O1.2) does not reference
   `OpenRouterEgressPermitting`. The one file that holds an API address only as a constant that a gated
   site uses (`OpenRouterLabelPhotoRequest.swift`) is listed by name as exempt; a new exemption is a
   reviewed change to the script. The check is a backstop (a file passes by naming the protocol);
   behaviour is proved by test 1, which records the use each site passes. The script's existing
   self-test fixture pattern proves the check fails.
7. **Records and exports decode unchanged.** Committed fixtures of food records (including a label
   photo entry with its `LabelPhotoManifest` and a reviewed web proposal), archives and food daily
   exports decode and re-encode byte for byte; no format version changes.
8. **Policy and engineering list agree.** A test reads `docs/privacy-policy.txt` and
   `docs/privacy-and-egress.md` from the bundle and the repository and checks the explicit mapping
   of section 6 (`OpenRouterUse.policyEntry` and `.egressRow`): every in-force case's policy entry
   (the opening words of its paragraph, such as `Key validation.`) is present in the policy's OpenRouter
   section, and its egress row (identified by its contract link) exists with "When" naming the switch.
   A use entry is a paragraph that starts with a `policyEntry` title; every use entry and every
   OpenRouter row maps back to at least one in-force case, and cases not in force map to nothing. The
   framing paragraphs (the opening paragraph, "While it is on", "Other uses are added" and "For every
   use") are pinned word for word, separately from the mapping. It also checks that the two kept sentences of section 3.5 are present word for word.
   The existing label photo verbatim test (`testTheLabelPhotoPrivacyRecordsAreInForceVerbatim`) is
   updated to the new text.
9. **Settings.** The OpenRouter section sits after Food search with the exact rows, copy and order of
   O1.1; the switch is off by default; building and toggling the section, and showing the label reads
   row, sends no request and creates no read session (`LabelPhotoSessions.count` unchanged); Food
   search no longer has the Web lookup row or the photo toggle, and its footer is verbatim.
10. **Journeys.** No removed string of O1.4 appears in any presentation type (a string search over
   `LabelPhotoText`, `NutritionLabelEntryText` and the web lookup views); the first-use sheet cannot
   be presented; the blocked row shows the right reason in order.
11. **Simulator journey checks** for web lookup and the label photo route (scripted), switch on and off,
   by `journey-qa`.

## 3. Amended documents (exact text, applied on approval in the implementation PR)

### 3.1 Label photo AI pre-fill v1

- **E4** becomes: `Only on the explicit Read label with AI tap, with OpenRouter turned on in Settings
  (O1); no background, prefetch or automatic re-read.` The one-time confirmation sheet and the
  egress statement it stood beside are replaced by the Settings consent and the privacy policy's
  OpenRouter section.
- **E7** gains: `The catalogue requests are sent only while OpenRouter is turned on (O1).`
- **E8** gains: `A key is validated only while OpenRouter is turned on (O1-D2).`
- **7.1**: the egress statement, under-button and first-use rows are struck, with a pointer to O1.4;
  **7.2**: the no key and key not validated rows point to the O1.4 blocked row; failed key rejected
  as O1.4.
- **9 (screen states)**: the Ready state no longer lists the egress statement.
- **17.22**: the "Read label photos with AI" switch and `labelPhoto.liveRoute.enabled.v1` are replaced
  by the consent switch of O1.1 and the matrix of O1.2; the `turnedOff` blocker becomes the O1.4 row;
  the live consent key is retired (O1.5). Everything else in 17.22 stands, including the internal
  TestFlight rule, whose scope sentence ("A build that contains the switch goes only to the internal
  testing group") becomes "A build that can reach the live label photo route goes only to the internal
  testing group", since every build now contains the consent switch; no build flag removes the route
  today, so every Release build that carries O1 is internal-only.
- **P6** becomes: `Explicit send. Nothing leaves the device until the user taps Read label with AI,
  with OpenRouter turned on in Settings (O1).` Its copy pointer stays 7.1 and its approval E4.
- **4.1**: the egress statement bullet is struck.
- **12 (architecture) and 14 (test plan)**: `LabelPhotoScreenModel.Environment` loses `hasConsented`
  and `recordConsent` and gains the gate's answer; the view model test "first-use sheet once" becomes
  "no first-use sheet; the blocked row while the switch is off".
- E1 to E3, E5, E6 and E9 to E16 are unchanged.

### 3.2 Generic food proposal integration v1

Architecture gate, presentation bullet: `explicit opt-in/key validation` becomes `the Settings ›
OpenRouter switch (O1) and key validation`. Added to the closed invariants: `No OpenRouter request
while the switch is off; the adapter asks OpenRouterEgressPermitting before every request.`

### 3.3 Pasted label AI text v1 and AI search by name v1

- Pasted label text **T8** (never approved, route closed by D38) is annotated: `If the route is ever
  reopened, the egress statement and first-use sheet are replaced by O1's consent.` No term is approved.
- AI search by name **A8** becomes: `Only on the explicit Send tap after A6, with OpenRouter turned on
  in Settings (O1); no prefetch, per-keystroke, background or automatic re-send.` A6's confirm-before-send
  view and its personal-data gate stay: they show the exact content and change what the user does.

### 3.4 Privacy and egress

Rules for every egress path, added after the first bullet:

```diff
+- **One OpenRouter consent** ([O1](openrouter-single-consent-v1-amendment.md)): every app request to OpenRouter, on every route, including key validation and keyless catalogue checks, is sent only while Settings › OpenRouter is turned on. It is off by default, and no earlier per-feature consent counts as it. Each OpenRouter use the app can make has a row in the table above and an entry in the privacy policy's OpenRouter section; a new use is added to both in the PR that wires it, after its own approval, and the switch's approval never extends to it.
```

Allowed egress, the "When" column of both OpenRouter rows, prefixed:

```diff
-| OpenRouter and its configured providers | Displayed food terms and captured public source text, ... | Only on an explicit web lookup, with the user's own validated key; ...
+| OpenRouter and its configured providers | Displayed food terms with the market set in Settings (when one is set) and captured public source text, ... | With OpenRouter turned on in Settings (O1), only on an explicit web lookup, with the user's own validated key; ...
-| ... | Only when the user taps Read label with AI on the Label photo screen, with the user's own validated key; on the first tap of a session, and on the first tap of each new local day, two catalogue requests ...
+| ... | With OpenRouter turned on in Settings (O1), only when the user taps Read label with AI on the Label photo screen, with the user's own validated key; on the first tap of a session, on the first tap of each new local day, and on the next tap after a check that could not connect, two catalogue requests ...
```

In force, internal testing only (two sentences):

```diff
-... Builds that contain the switch go to the internal TestFlight group only ...
+... Builds that can reach the live label photo route go to the internal TestFlight group only ... No build flag removes the route today, so every Release build that carries O1 is internal-only until an external build leaves the route out by a change of its own ...
-... and in a Release build only through Settings › Food search › Read label photos with AI, which is off by default (section 17.22, owner approval 14 November 2026).
+... and in a Release build only with Settings › OpenRouter turned on and a key saved, which is off by default (section 17.22, owner approval 14 November 2026, as amended by O1).
```

The market tag is sent today (`GenericFoodProposalReviewView` adds it to the request terms), and today it is
disclosed on the Food market screen (`Web lookup sends the chosen market with your food terms.`, which
stays) and in the review screen's closing note, which O1.4 removes; the privacy policy has never said
so. Naming it in the row and in the policy's web lookup entry is a new disclosure of an
existing payload, not a wider one.
The catalogue clause records what `LabelPhotoReadSession` already does (a check that could not connect
is not kept); it is a new disclosure of existing behaviour. Key validation (`v1/key`, the key only) is covered by the web lookup row's contract and the policy's
"Key validation" entry, and the catalogue checks by the label photo row, so no row is added. No
destination, payload, cap, retry rule or retention statement changes.

### 3.5 Privacy policy

Replaces, in "Optional online food search", every sentence about OpenRouter (from "Web nutrition
review requires your own OpenRouter API key" to the end of the paragraph beginning "Your OpenRouter key
uses this-device-only Keychain storage", and its OpenRouter links), and the label photo paragraph. The
Open Food Facts sentences and link and every other section stay; the Exa link moves into the new
section's link list, beside the sentence that names Exa. The new
section follows "Optional online food search":

```text
OpenRouter

The app uses OpenRouter only if you turn on Use OpenRouter for food lookups and label reading in Settings › OpenRouter. It is off by default. While it is off, the app sends nothing to OpenRouter: no lookup, no label photo, no key validation and no model check. Turning it off stops every further request; requests already sent cannot be recalled. It does not delete your key, which you remove separately with Remove key. Lookups and label reads need your own OpenRouter API key, kept in this-device-only Keychain storage, without sync or backup migration, and validated in the current session. Requests may incur charges on your account; set account and key limits at OpenRouter.

While it is on, the app uses OpenRouter only in these ways, each only when you start it:

Key validation. When you save or revalidate a key. Sends only the key, to check it; never food terms or any other data.

Web lookup. When you tap Look up or start a source review. Opening the screen, typing food terms or storing a key does not submit a food query. Each review uses at most one search request; for each source tried, one source-selection request, three website connections including redirects, one extraction request and one applicability check; and if the first source gives no usable values, one more suggested source may be tried in the same way, without a new search. The app has no monetary spending cap for web lookup; set credit limits at OpenRouter. A search sends the displayed food terms, tagged with the food market set in Settings when one is set, through OpenRouter to its configured model and the Exa search service; source selection also uses the returned page titles, addresses and excerpts. Supplying a public HTTPS source address skips search and source selection. The app fetches the chosen public page directly, without sending your key to that publisher. The captured page text and the displayed food terms then go to OpenRouter's configured extraction and applicability providers for a structured proposal and a separate check against the requested food. A page is sent whole up to a fixed size; for a larger page only its nutrition tables and lists, the lines and headings around them, its main heading and its structured data are sent, and the review says that only part of the page was read. When a page gives more than one set of values for the same food, those sets are also sent for the check. Never sent: Apple Health records, saved food or diary history, notes, receipts, photos or audio. If a model request fails for a temporary reason, such as a lost connection, a timeout or a busy service, the app may send the same request again, unchanged, at most twice; it never retries fetches of publisher pages. The current app uses Azure-hosted Luna for discovery, source selection and applicability checking and xAI-hosted Grok for extraction; Jev ranking is not enabled in the default flow. Avoid entering private or sensitive information in food terms.

Label photo reading. Available only in internal test builds. When you tap Read label with AI. The photo may be one you took, chose from your library or pasted on the Nutrition label screen; the app reads the clipboard only when you tap Paste on that screen. Sends the part of the photo you cropped, made smaller and re-encoded with location, camera and other metadata removed, with a fixed instruction; OpenRouter passes it to one named model endpoint (currently Gemini 4 Argon on Google Vertex) with no fallback to other providers. Before the first read of a session and of each day, and again after a check that could not connect, two catalogue requests with no key and no data confirm that endpoint. Never sent: your food name, brand, food log, notes or Apple Health data. The model's answer pre-fills the label values, which you check and correct before anything is saved. A failed request is retried at most twice within the same tap, and reading is limited to 30 photos and $0.50 of reported cost a day. Avoid photographing anything other than the nutrition table.

Other uses are added to this list only in the release that starts them, after their own approval.

For every use: model requests require endpoints classified by OpenRouter for zero data retention and no data collection, with no provider fallback. These controls do not establish the retention policy of search services, publisher websites or OpenRouter's own account and usage records, which include the model, token counts, cost and time of each request, kept under OpenRouter's terms. Search-service terms may permit query data to be used for service improvement or model training; model-retention settings do not prevent that. Providers and publishers receive ordinary network information such as IP addresses and request details. Those services apply their own terms; the app cannot independently verify or erase their logs. Requests already sent cannot be recalled, and removing your key or turning OpenRouter off cannot erase provider records. Read the applicable terms before turning it on:
OpenRouter privacy: https://openrouter.ai/privacy/
OpenRouter terms: https://openrouter.ai/terms
OpenRouter model retention controls and their scope: https://openrouter.ai/docs/guides/features/zdr
OpenRouter third-party provider policies: https://openrouter.ai/docs/guides/privacy/provider-logging
Exa privacy: https://exa.ai/privacy-policy
```

Kept in "Optional online food search", after its Open Food Facts sentences, with the wording
adjusted only for the switch: `To stay offline, keep optional database search disabled, keep
OpenRouter turned off and avoid barcode-lookup actions.` (today: "keep optional database search
disabled and avoid manual web review and barcode-lookup actions"; with the switch, turning OpenRouter
off is the stronger form of avoiding web review, so nothing is lost). The request budget sentence corrects the key screen's current wording, which counts one source only
although `GenericFoodProposalReviewer.run` tries a second suggested source when the first gives no
usable values; the corrected sentence states existing behaviour and widens nothing. Before the
implementation PR is opened, the old and new policy texts are compared sentence by sentence and the comparison is recorded
in the PR, so no stated fact is dropped.

If O1-D2 is decided the other way (validation allowed with the switch off), the opening sentence
reads `While it is off, the app sends nothing to OpenRouter except the key itself when you save or
revalidate it: no lookup, no label photo and no model check.`, and test 8 checks the sentence that
matches the recorded decision.

The "Effective" date moves to the release date of the implementing build. In "Local food records and
notes", "Remove your OpenRouter key and disconnect Drive before deleting the app" stays as it is.

## 4. What stays closed

- **Egress does not widen.** Destinations, payloads, routing, per-request and daily caps, retries,
  catalogue checks, key handling and on-device retention are exactly as their contracts approve. The
  switch only adds a condition before each request.
- Nothing is saved without the owner's Log; AI output, citations or confidence never authorise
  nutrition by themselves.
- Explicit loading, empty, partial, blocked, failed and no-data states stay; a failure that may have
  sent data still says so.
- Estimates stay labelled ("est." beside each estimated value on Confirm, as decided on 20 November
  2026), and unknown stays unknown.
- Stored provenance on food records ("read by model on provider through OpenRouter, checked by you")
  is unchanged, and so is every record, archive and export format.
- The photo route stays internal-TestFlight-only until the owner reviews the App Store privacy answers.
- HealthKit stays read-only; no Health data reaches any OpenRouter route.

## 5. Compatibility and rollback

- **Stored formats.** None changes. Consent lived only in `UserDefaults`, and no record, archive or
  export field carries consent, the switch or egress state (`LabelPhotoManifest.routeVersion` records
  the route, not the consent). Older builds decode everything a new build writes.
- **Update.** Every OpenRouter route is off until the owner turns the switch on once (O1.5). The key
  and its Keychain item are untouched.
- **Rollback.** An older build ignores `openRouter.consent.v1` and finds its own keys
  (`labelPhoto.liveRoute.enabled.v1`, `labelPhoto.egressConsent.live.v1`) as it left them, so it
  behaves as before the update. No data migration runs in either direction.

## 6. Architecture gate

- **Responsibilities.**
  - **Domain** (`FoodLedgerDomain`): none. Consent is not a food rule.
  - **Application** (`FoodLedgerApplication`):
    - the closed `OpenRouterUse` list: in force `keyValidation`, `webLookup`, `labelPhotoRead`,
      `labelPhotoCatalogueCheck`; not in force `pastedLabelTextRead`, `pastedLabelTextCatalogueCheck`.
      Each case carries `isInForce`, `policyEntry` (the opening words of its privacy policy paragraph,
      or nil) and `egressRow` (the contract link that identifies its `privacy-and-egress.md` row, or
      nil). The mapping is many to one: `keyValidation` and `webLookup` map to the web lookup row,
      `labelPhotoRead` and `labelPhotoCatalogueCheck` to the label photo row and its entry; cases not in
      force map to nothing. Later routes add cases in their own contracts.
    - the consumer-owned port `OpenRouterEgressPermitting`, one method,
      `permits(_ use: OpenRouterUse) -> Bool`;
    - an application-owned `OpenRouterKeyState` (`missing`, `notValidated`, `valid`) and one pure
      `OpenRouterAccess.blockedReason(consentOn:keyState:)` returning the O1.4 reason or nil, in the
      order of that table. The label photo screen's `LabelPhotoScreenModel.KeyState` maps case for case
      to it; both web lookup view models derive it from `hasSavedKey` and `keyIsUsable` (`keyIsUsable`
      gives `valid`, else a saved key gives `notValidated`, else `missing`);
    - the new outcome cases `FoodWebDiscoveryError.notPermitted`, `LabelImageReadingFailure.notPermitted`
      `LabelImageReadingFailure.notPermittedAfterSending` and `LabelPhotoRouteCheckFailure.notPermitted`.
      In `OpenRouterFoodProvider.request` the gate is asked before each attempt and throws
      `.notPermitted` before the attempt starts, so a refusal is never classified by
      `FoodWebModelCallRetryPolicy` and never retried or slept on; the exhaustive switches that must
      name the new case (`FoodProposalSelectionFailure.init`, the retry outcome mapping,
      `LabelPhotoText.failure`) give it an explicit mapping, unreachable where the throw precedes them,
      pinned by a test;
    - `LabelPhotoReadSession`: asks the gate before the catalogue check and before reserving the tap,
      and does not record a `notPermitted` check as a day failure (O1.2);
    - `GenericFoodProposalReviewer`: asks the gate before each `capture.capture` and before each model
      call.
  - **Infrastructure**: `OpenRouterFoodProvider` (`FoodGenericSearch`), and `OpenRouterLabelPhotoAttempt`,
    `OpenRouterLabelRouteChecker`, `OpenRouterPastedLabelAITextAttempt` and
    `OpenRouterPastedLabelAITextRouteChecker` (`FoodLabelPhotoCapture`) take an
    `OpenRouterEgressPermitting` at construction, as a required parameter with no default (so missing
    wiring does not compile; existing tests pass a permitting test double), and ask it at each request
    site of O1.2.
    `OpenRouterPastedLabelAITextRouteChecker` builds its own photo checker inside its init, so its init
    takes the gate and passes it on. `OpenRouterTransport`, `ScriptedLabelPhotoTransport` and
    `PublicFoodSourceCapture` do not change (`HTTPSFoodSourcePageAcquirer` serves only the Gemini
    review, which the app does not construct).
  - **Developer tools** (`Tools/LabelPhotoE13`, `Tools/PastedLabelAITextEval`,
    `Packages/FoodLedgerKit/Tools/FoodProposalProbe`):
    they construct the same adapters (and `Tools/LabelPhotoE13` also `LabelPhotoReadSession`), so each
    passes a tool-local gate that permits its own uses to every one of them. They
    run on the owner's Mac under their own approved terms (E13, T1 to T7) and are not app egress; their
    terms do not change.
  - **Presentation** (`FoodLedgerPresentation` and the app target): the shared blocked row view and its
    copy type, the label photo blocker change, the web lookup row change, the trimmed key screen, the
    removals and string changes of O1.4, and the sectioned privacy policy screen with its anchor. The
    Settings section, `OpenRouterConsentPreference` (conforming to the port, reading the persistent
    domain only) and the Debug-only seeding argument live in the app target.
  - **Composition root**: builds one preference, passes it to every OpenRouter adapter, to the web
    lookup orchestration (`GenericFoodProposalReviewer.init`, a required parameter too, since
    `FoodProposalProbe` constructs the reviewer), to the label photo session, to
    `FoodWebDiscoveryViewModel` and `GenericFoodProposalReviewViewModel`, and to every journey, and resolves the label photo
    mode from it (O1.2 matrix). The app's preference permits only in-force uses, so the pasted label
    text uses are always refused in the app.
- **Dependency direction.** Unchanged: infrastructure and presentation depend on the application
  port; the application depends on nothing new; `UserDefaults` stays in the app target. No new
  package target. `check-boundaries.sh` gains one check (O1.6 test 6): every OpenRouter request site
  references the gate.
- **Ports.** One new consumer-owned port, `OpenRouterEgressPermitting`. No generic consent framework,
  no per-route consent type and no repository. Framework types do not cross it (a Boolean answer for
  a closed enum).
- **Invariants.** Switch off: zero OpenRouter requests and zero publisher page fetches on every route,
  enforced at the request sites. Default off. Consent is never read from launch arguments in Release,
  and no retired key is ever read as consent. A refusal never changes key or route state. Request
  bytes with the switch on are unchanged. No stored format changes. The privacy policy's OpenRouter
  section and the egress table agree with the closed list of uses through its explicit mapping.
- **Extension axes.** A new OpenRouter use is a new `OpenRouterUse` case with its mapping, a policy
  entry, an egress row and a request site that takes the gate, all in the PR that wires it after its
  own approval; tests 1, 6 and 8 fail until all exist. A new provider is not an extension of this
  switch; it needs its own contract and consent decision.
- **Contract tests.** Section O1.6.

## 7. Decisions for the owner

Asked one at a time on #551, each with a recommendation. Approval of the amendment as a whole
(sections 2 to 6) is asked last, after these.

- **O1-D1. The daily label read count.** **Decided as recommended (20 November 2026).** Recommendation: **Settings only**, as the `Label photo reads
  today` row of O1.1, and in the journey only when the cap blocks a read (the existing daily limit and
  paused blockers). The alternative keeps the under-button line on the Label photo screen.
- **O1-D2. Key validation while the switch is off.** **Decided as recommended (20 November 2026).**
  Recommendation: **blocked too**, so "off sends
  nothing to OpenRouter" holds without exception and the policy can say so plainly. The key can still
  be pasted and saved locally with the switch off. That is new behaviour: today a key is saved only
  after it validates (`FoodWebDiscoveryViewModel.validate(key:saveNewKey:)`). With the switch off the
  button reads `Save key`, saves the key to the Keychain unvalidated and shows `Key saved. Turn on
  OpenRouter in Settings to validate it.`. Saving a key this way clears the session's in-memory
  `validatedKey` and `keyIsUsable` and bumps the credential generation, exactly as saving a new key does
  today, so a key validated earlier in the session is never sent in place of the new one. The Settings
  detail then reads `Revalidate key`, and turning
  the switch on validates nothing by itself (the owner taps Revalidate saved key, or the journey's
  blocked row says to). A test proves nothing is sent while saving. The alternative allows validation with
  the switch off, since it sends only the key, but then "off" has an exception the policy has to
  explain.
- **O1-D3. The label photo switch.** **Decided as recommended (20 November 2026).** Recommendation: **replace it with the consent switch**: the photo
  entry appears when OpenRouter is on and a key is saved (in builds that contain the route), so there
  is one switch, not a consent plus a feature switch. The alternative keeps "Read label photos with AI"
  as a feature switch under Settings › OpenRouter, which would leave two OpenRouter switches.

## 8. Review record

- **Architecture gate, first round (20 November 2026): PASS WITH CHANGES.** All fourteen findings
  taken. A refusal is its own outcome (`notPermitted`) on web lookup, the label photo read and the
  catalogue check, never a rejected key or a day-long route failure; the label photo gate moved from
  the transport to the attempt and the checker; the daily count rule for a refusal is stated; the web
  lookup orchestration is gated before page acquisition; two policy sentences that the first draft
  dropped are kept; the policy test uses an explicit use-to-entry and use-to-row mapping; the unwired
  pasted label text adapters take the gate under uses not in force, and the boundary script checks
  every request site; O1-D2's unvalidated saved key is stated as new behaviour; consent is read from
  the persistent domain only, with a Debug-only seeding argument for UI tests; the privacy screen's
  split and anchor are specified; every key-rejected string is named; the market tag is recorded in
  the egress row; request goldens are committed fixtures. The developer tools that construct the
  gated adapters were added after the gate, in section 6.
- **Architecture gate, second round (20 November 2026): PASS WITH CHANGES.** It confirmed the round-1
  changes are present. All nine findings taken: the daily count rule now states what
  `LabelPhotoReadSession` already does with a `.notSent` attempt (first-attempt refusal released,
  retry refusal reconciled on sent attempts), where the first draft wrongly said a tap was counted;
  `notPermitted` is rethrown unwrapped at every web lookup site that rethrows a rejected key and never
  becomes a partial failure, a usable review or an acquisition failure, with the pre-capture check
  outside the capture handler; key validation asks the gate before clearing usability; the policy
  text keeps the key screen's facts (no sync or backup migration, the per-review request budget, no
  monetary cap), says storing a key "does not submit a food query", and moves the Exa link; the market
  tag is called a new disclosure, since the policy never stated it; the claim about existing UI tests
  is corrected (there is no UI test target); the seeding argument takes `on|off` through a pure
  resolver with a build parameter; the read closure's switch-off refusal shows the blocked row; the
  gate is a required parameter; the policy screen's heading list is pinned.
- **Architecture gate, third round (20 November 2026): PASS WITH CHANGES.** Rounds 1 and 2 confirmed
  against code. All ten findings taken: each request site names the use it asks for, and the catalogue
  fetch takes its use from the caller so the pasted text checker cannot borrow the photo use; both web
  lookup view models and the reviewer receive the gate, and `.notPermitted` maps to the blocked row; a
  refused retry after a sent attempt keeps the "may already have reached OpenRouter" line; P6, 4.1,
  section 12 and the test plan of the label photo contract get their amended text; the market tag
  claim is corrected (the Food market screen already discloses it); four policy wording fixes,
  including the alternative opening sentence if O1-D2 goes the other way; an exact heading rule; a link
  on the key screen; the label reads row reads the ledger without a session and shows only when the
  route can be reached; the boundary exemptions trimmed and the script called a backstop.
- **Architecture gate, fourth round (20 November 2026): PASS WITH CHANGES.** All six findings taken:
  the policy's web lookup request budget is stated per source tried, since the reviewer tries a second
  suggested source (the key screen's current sentence counts one source only, so the policy text
  corrects it rather than publishing it); a named `.notPermittedAfterSending` case lets the screen
  show "may already have reached OpenRouter" only when an attempt was sent; the read closure tells
  switch off from a removed key; the policy test pins the framing paragraphs separately from the use
  mapping; the title block rule is stated; the session's gate uses are named.
- **Architecture gate, fifth round (20 November 2026): PASS WITH CHANGES.** No blocking finding; all
  six taken: a removed key at the read closure gives the existing `.keyMissing` (the closure returns
  route-unavailable today, so the earlier "existing no-key path" was wrong); the orchestration is named
  `GenericFoodProposalReviewer`, not the result struct; the provider's gate throws before an attempt
  so a refusal is never retried, with the exhaustive switches named; `.notPermittedAfterSending` is
  listed; the pasted text checker's init passes the gate to its own photo checker, and E13 gives its
  session a tool gate; the policy's catalogue sentence adds the check after a failed connection, and
  the market tag is "when one is set".
- **Architecture gate, sixth round (20 November 2026): PASS WITH CHANGES.** No blocking finding; all
  five taken: an application-owned `OpenRouterKeyState` with the mappings from both journeys; the gate
  is asked after any backoff wait, immediately before each send, and the retry test counts one wait;
  the internal-only rule is rescoped to builds that can reach the live photo route, in both the egress
  file and 17.22, with every O1 Release build internal-only; the key screen wording follows O1-D2, and
  saving a key with the switch off clears the session's validated key; the egress row gains the
  catalogue recheck clause the policy states.
- **Architecture gate, seventh round (20 November 2026, at `d43684c0`): PASS WITH CHANGES.** No blocking
  finding; all three taken: the app fetches publisher pages through the reviewer's
  `FoodDocumentCapturing` (`PublicFoodSourceCapture`), not `HTTPSFoodSourcePageAcquirer`, so the gate
  sits immediately before `capture.capture` and the tests count that double; the read closure takes its
  key state from the mode's own source, so scripted runs need no real key, and a not-validated key
  passes through as today; the pasted label text adapters get named refusal cases, with the `Codable`
  not-sent enum's new raw value stated as additive and outside every record.
- **Architecture gate, eighth round (20 November 2026, at `3574ca21`): PASS.** No finding. It checked
  every request site and use, the refusal paths, the key state ordering, the layering, section 3.5
  sentence by sentence against the current policy and key screen, the replaced egress text and the
  stored formats.
- **Owner decisions (20 November 2026).** O1-D1, O1-D2 and O1-D3 decided as recommended, asked one at a
  time.
