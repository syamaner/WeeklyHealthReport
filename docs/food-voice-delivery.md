# Typed and on-device food capture — architecture gate

Issue #96 extends the delivered pasted-list input, not the nutrition matcher or
ledger schema. Typed text remains available without any speech permission.

- The existing pure classical parser proposes quantities, units and identity
  modifiers. Recognition output is editable query text, never nutrition truth.
- The app reuses the existing injected `OnDeviceSpeechCapturing` capability and
  tested `DailyNoteSpeechController` lifecycle. Its callback writes only to a
  temporary food dictation draft, never to the ledger or daily notes.
- The Speech adapter accepts bounded contextual vocabulary from current saved
  food names, brands and units. It checks on-device support and requires on-device
  recognition; no server fallback or audio file is introduced.
- Explicitly accepted transcript text enters the same list editor and per-line
  candidate/quantity review as typing. Uncertain speech fragments require review
  or discard before transfer. Backgrounding/navigation cancels live capture.
- The composition root provides local vocabulary; pure vocabulary/draft policies
  and synthetic speech fakes protect limits, cancellation, numeric review and the
  absence of automatic nutrition writes. Existing notes behaviour stays intact.

Apple documents `requiresOnDeviceRecognition` as preventing network audio only
when the recognizer supports on-device recognition. Both checks remain mandatory.
[`contextualStrings`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)
is a recognition hint, not a correctness guarantee; keep the list at most 100
brief phrases. See also
[`requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

Physical speech accuracy, permission prompts and audio lifecycle require a
separately authorised device check. This work does not launch a device, access a
microphone or make a speech-provider call during development. No personal examples
or audio enter repository fixtures.

## Review and provenance

Open **Food logging → Paste Food List → Dictate**. Tap the microphone to request
permission and start, then Stop. Final text is held in the editable food draft;
uncertain fragments have their own accept/discard review. Check every numeric value
and unit, put items on separate lines, and explicitly use the text in food review.
Typing or another capture clears the numeric-review acknowledgement. Unsupported
spoken quantities remain unresolved in the parser and must be edited manually.

Transferring appends to existing list text without preparing, searching or saving.
It is disabled once a queue is prepared and rejects oversize input without losing
either draft. The shared review still requires candidate and quantity confirmation.
The input evidence is labelled `reviewed_food_text_with_on_device_speech` and kind
`manual`: it records user-reviewed mixed text, not a verbatim audio transcript or
independently verified food. Starting a new list resets the capture label.

Saved-library lookup retains the accepted matcher's exact normalised alias path
(case, punctuation and its existing lexical aliases); no new fuzzy auto-match
threshold is introduced. Ambiguous or absent matches use the normal candidate or
manual fallback. Google inventory access is not a prerequisite for this flow.

## Deferred physical check

With separate device authority, use invented foods in a supported locale and
Airplane Mode. Check first-use/denied/restricted permissions, unavailable locale,
brief capture, pauses, wrong numbers, Stop timeout, audio interruption, background
and dismissal. Verify that no food saves before explicit confirmation, no audio
file is retained, and typing works throughout. Record device/iOS/locale and any
recognition differences; simulator state tests do not establish speech accuracy.

Integrated validation after PR #133: 140 package tests, 258 unsigned simulator tests, Xcode
static analysis, 15 matching-evaluation tool tests and unchanged frozen report
verification pass. The existing app models/formatting/presentation gate remains
96.49%; this is not a claim about all voice-UI lines or physical recognition.
