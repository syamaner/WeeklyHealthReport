# Unreleased changes since 0.3.0 (29)

Release notes to carry into the next TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here. The entries since build 26 moved to the [0.2.0 (28) and 0.3.0 (29) record](internal-testflight-0.3.0-build29.md).

- **Pasted label: a per 100 header the reader cannot classify now declines** (#375). A Taiwan paste whose column header was written in English with an unfamiliar gram spelling (`Per 100gm`, `per 100 grams`) or as a bare `Per 100` used to reach Confirm with per 100 values stored as per serving. It now declines with the message that the values could not be matched to their rows and columns, so nothing is stored under the wrong basis. Accepted readings are unchanged (`pasted-header-basis-guard-v1`).
