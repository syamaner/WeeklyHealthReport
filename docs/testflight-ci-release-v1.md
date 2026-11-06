# Internal TestFlight release from GitHub Actions, v1

Status: **draft for owner review** (issue [#85](https://github.com/syamaner/WeeklyHealthReport/issues/85)). The workflow is checked in but inert: it runs only by manual dispatch, and its release job cannot receive credentials until the owner creates the protected `testflight` environment and its secrets. Nothing here authorises creating credentials, storing secrets, creating the environment, dispatching the workflow or uploading a build; each of those is a separate owner step.

On 16 October 2026 the owner approved storing the App Store Connect API key as a GitHub secret, on the condition that it is set securely and nothing can leak it. This document is how that condition is met.

Files:

- [`.github/workflows/testflight-release.yml`](../.github/workflows/testflight-release.yml): the workflow.
- [`.github/scripts/testflight_guard.py`](../.github/scripts/testflight_guard.py): credential-free source guard and What to Test resolver.
- [`.github/scripts/testflight_asc.py`](../.github/scripts/testflight_asc.py): App Store Connect client (standard library only; reads the key from the path in `ASC_KEY_PATH`).
- [`.github/scripts/testflight_verify_ipa.py`](../.github/scripts/testflight_verify_ipa.py): IPA inspection before upload.
- [`.github/scripts/tests/test_testflight_release.py`](../.github/scripts/tests/test_testflight_release.py): synthetic tests, run by `iOS CI` with the other helper tests and again by the release guard.

The manual route this automates is recorded in [Internal TestFlight 0.2.0 (25)](releases/internal-testflight-0.2.0-build25.md).

## What it does and does not do

It archives one exact commit on `main`, signs it for App Store distribution, checks the exported IPA, uploads it once, waits for Apple to process it, sets What to Test and adds it to the existing Internal Testing group, then reads every write back.

It never adds a build to an external group, never creates or enables a public link, never submits for Beta App Review or App Review, never changes tester membership and never changes the app record. External testing stays a manual step with its own approval. The app's data egress ([privacy and egress](privacy-and-egress.md)) is unchanged: the pipeline handles signing material and a build, not user data, and the only destination is Apple, which the manual release already used.

## 1. Trigger

- `workflow_dispatch` only. There is no `push`, `pull_request`, `pull_request_target`, `schedule` or `workflow_run` trigger, so merges, pushes and pull requests never start a release.
- `main` only, enforced three times: the job condition (`github.ref == 'refs/heads/main'`), the guard script, and the environment's deployment-branch policy, which refuses to hand secrets to any other ref.
- Inputs:
  - `build_number` (required): the fresh `CFBundleVersion`. The workflow never renumbers. The guard accepts a positive integer of at most six digits, and the App Store Connect preflight refuses a number this app has already used on any version.
  - `release_doc` or `what_to_test` (exactly one): either a path such as `docs/releases/internal-testflight-0.2.0-build25.md`, whose first `text` block under `## What to Test` is used, or the text itself. Reading it from the reviewed release record is the recommended route, because then the text is in Git and approved through review.
  - `dry_run` (default on): archive, export and verify, then stop before upload. A dry run does not consume the build number.
- The marketing version comes from the project (`MARKETING_VERSION`, which must have one value), as it did for 0.2.0. The build number is passed as `CURRENT_PROJECT_VERSION` at archive time, as it was for 0.2.0.
- Every attempted upload consumes its build number. A failed or ambiguous run is never re-run; dispatch again with a higher number after checking App Store Connect.

## 2. GitHub Environment `testflight`

| Setting | Value | Why |
| --- | --- | --- |
| Required reviewer | the owner (`syamaner`) | No credential is released to a job until the owner approves that run. |
| Prevent self-review | off | The owner is the only reviewer and usually also the dispatcher; on would make approval impossible. |
| Administrators bypass | off | Approval is required even for the owner's own admin account. |
| Deployment branches | custom policy, branch `main` only | A workflow edited on another branch cannot reach the secrets. |
| Wait timer | none | Approval is the control. |

Environment secrets (never repository or organisation secrets):

| Secret | Contents |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | Issuer id |
| `ASC_PRIVATE_KEY` | The `.p8` file contents, as read from stdin |
| `DRIVE_OAUTH_CLIENT_ID` | Public native iOS Google OAuth client id (embedded in the IPA, but kept out of Git) |
| `DRIVE_OAUTH_REDIRECT_SCHEME` | Its reverse redirect scheme |
| `DIST_P12_B64` | Base64 of the Apple Distribution identity `.p12` |
| `DIST_P12_PASSWORD` | The `.p12` export password |
| `DIST_PROFILE_B64` | Base64 of the App Store distribution provisioning profile |

Non-secret identity is reviewed in the workflow file instead: team `MDNYU95CGT`, bundle `com.otherweather.ReportWeeklyHealth`, app `6812893951`, Internal Testing group `a626bae5-2ff3-4221-917d-435a826662b8`.

## 3. Signing on a runner

A hosted runner has no distribution certificate, so the release needs one of two routes.

| | Cloud-managed signing with the API key | Imported identity (recommended) |
| --- | --- | --- |
| How | `-allowProvisioningUpdates` with the key; Apple signs with a cloud-managed certificate | `.p12` and App Store profile from environment secrets, imported into a temporary keychain; manual signing |
| Key role | Apple's [cloud-managed certificate help](https://developer.apple.com/help/account/certificates/cloud-managed-certificates) grants cloud signing to Admins and Developers through an extra App Store Connect permission; App Manager is not listed, and community reports show API keys needing Admin. The key would have to be widened to Admin, a team-wide role. | App Manager is enough (it is only used for upload and TestFlight calls) |
| Determinism | Apple may create or change certificates and profiles during the run | Signing inputs are fixed and reviewable; no provisioning changes |
| Matches issue #85 | No (the issue rules out `-allowProvisioningUpdates` and cloud signing) | Yes |

Recommendation: **imported identity, with a dedicated Apple Distribution certificate for CI** and an App Store profile named, for example, `WeeklyHealthReport CI App Store`. The key stays App Manager. What the owner must do: create that certificate and profile in the developer portal, export the identity as a `.p12` with a strong, generated password, and set the three signing secrets (commands in section 7). Nothing changes on the existing key.

How the workflow signs: it writes the git-ignored `Config/Signing.local.xcconfig` with `DEVELOPMENT_TEAM` and `PROVISIONING_PROFILE_SPECIFIER`, which only the app and test targets include, so the profile never reaches Swift package targets. It passes `CODE_SIGN_STYLE=Manual` and `CODE_SIGN_IDENTITY="Apple Distribution"` on the archive command line. The first dry run must prove this combination; if the app target's own `CODE_SIGN_STYLE = Automatic` wins over the command line for any setting, the fix is a reviewed project change, never `-allowProvisioningUpdates`.

## 4. No-leak rules and where each is enforced

| Rule | Enforcement in the workflow |
| --- | --- |
| Third-party actions pinned by full commit SHA | The only action is `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), the same pin `iOS CI` uses. No upload-artifact, cache or marketplace actions. |
| Least privilege token | Workflow `permissions: contents: read`; the guard job adds `actions: read` only to read `iOS CI` results; `persist-credentials: false` on every checkout. |
| No `pull_request_target`, no PR or fork runs | Only `workflow_dispatch`; both jobs require `github.repository == 'syamaner/WeeklyHealthReport'` and `refs/heads/main`. |
| Secrets only through `env:` | No `${{ secrets.* }}` or `${{ inputs.* }}` appears inside a `run:` body. Each secret is mapped only into the step that needs it, and every value is quoted. |
| Key on disk only under `$RUNNER_TEMP`, `umask 077` | Written with `printf '%s\n' "$ASC_PRIVATE_KEY"` (a shell builtin, so not visible in the process list) into `$RUNNER_TEMP/asc/private_keys/AuthKey_<id>.p8`; the ASC client refuses a key file readable by group or others. |
| Key never in arguments | `altool` finds the key through `API_PRIVATE_KEYS_DIR`; the Python client passes the file path, not the contents, to `openssl`. `xcodebuild` never receives the key (no provisioning updates). |
| No tracing | Default shell is `bash --noprofile --norc -euo pipefail` (no `-x`), and every script starts with `set +x`. |
| No configuration dumps | No `xcodebuild -showBuildSettings`, `env`, `printenv`, `set` or `cat` of a secret file. Validation uses `grep -q` and regular expressions that print only a fixed error. |
| Transient keychain password | Generated per run with `openssl rand`, masked with `::add-mask::`, never stored. |
| Clean up even on failure | The last step runs with `if: always()`: it deletes the keychain, restores the keychain search list, removes the installed profile, `$RUNNER_TEMP/asc`, `$RUNNER_TEMP/signing`, build products and both local xcconfig files. |
| No artefacts | The workflow uploads no artefact at all. The IPA exists only on the ephemeral runner until cleanup; the job summary holds hashes and identifiers only. |
| One release at a time | `concurrency: testflight-release` with `cancel-in-progress: false`, so a second dispatch waits and never cancels a run that may have uploaded. |
| No re-runs | Both jobs require `github.run_attempt == 1`, and the release job checks it again in its first step, because **Re-run failed jobs** would otherwise reuse the guard's earlier outputs. |

### Why the design never relies on masking

GitHub redacts registered secret values from logs, but that is a best-effort exact-match filter. GitHub's own guidance is not to rely on it for structured or multi-line values, and it cannot recognise a transformed copy: the base64 of a `.p12`, a single line of a PEM key, a substring, a URL-encoded or JSON-escaped form. The `.p8` key is multi-line, and the `.p12` and profile are base64 blobs, so the design treats masking as a last resort and instead never writes any secret, or anything derived from one, to standard output or standard error. The repository is public, so its run logs are public too; that makes this rule non-negotiable.

## 5. Steps

Job `guard` (Ubuntu, no environment, no secrets):

1. Check out `github.sha` without persisted credentials.
2. Run the synthetic release-helper tests.
3. `testflight_guard.py source`: dispatch event, upstream repository, `refs/heads/main`, first attempt, full SHA, valid build number, exactly one What to Test source (path confined to `docs/releases/`, at most 4,000 characters), one `MARKETING_VERSION`, and a completed, successful `iOS CI` push run on `main` for this exact SHA. Outputs SHA, version and build number.

Job `release` (macOS 26, environment `testflight`; waits for the owner's approval before any step runs):

1. Check out the guard's SHA; confirm `HEAD` equals it, the tree is clean and this is attempt 1; print `xcodebuild -version`.
2. Resolve What to Test into a temporary file.
3. Write the API key (section 4).
4. **Preflight** App Store Connect: the group belongs to app `6812893951`, is internal, has no public link; the build number is unused for this app.
5. Import the distribution identity into a temporary keychain; require exactly one Apple Distribution identity; install the profile by UUID.
6. Write the git-ignored OAuth and signing xcconfig files after validating that the client id has the native-app form and the scheme is its exact reverse.
7. **Archive** Release with manual signing and `CURRENT_PROJECT_VERSION=<build>`; no `-allowProvisioningUpdates`.
8. **Export** locally (`destination` `export`, `method` `app-store-connect`, `testFlightInternalTestingOnly` true, `manageAppVersionAndBuildNumber` false, `uploadSymbols` true). The `destination upload` route failed JWT verification in the manual release, so it is not used.
9. **Verify** the IPA: bundle id; version and build; `ITSAppUsesNonExemptEncryption` explicitly false; HealthKit, camera, microphone and speech purpose strings; Drive OAuth values not `MISSING`, equal to the protected values, the scheme registered as a URL scheme and the exact reverse of the client id; entitlements a dictionary with `get-task-allow` false, `application-identifier` `MDNYU95CGT.com.otherweather.ReportWeeklyHealth`, the team identifier and HealthKit; `codesign --verify --deep --strict`; embedded profile for the same team and app, no device list, not debuggable, not expired. Failures name the check, never the values.
10. Stop here when `dry_run` is on.
11. **Upload** once with `xcrun altool --upload-app`. Success requires exit status 0 and a delivery UUID. Anything else is reported as "outcome not confirmed" and the run stops: a red run does not prove Apple lacks the build.
12. **Distribute**: poll `GET /v1/builds` (filtered by app, version and build; pagination followed; duplicates refused) until `VALID`, failing on `FAILED` or `INVALID` and stopping after 45 minutes with an instruction to check read-only. Refuse `usesNonExemptEncryption` true. PATCH every `betaBuildLocalization` with the What to Test text and read it back; POST the build to the internal group once and confirm it through `GET /v1/betaGroups/{id}/builds`.
13. **Summary** (always): mode, SHA, version and build, bundle, Xcode version, profile name, UUID and expiry, IPA SHA-256, check result, delivery UUID, Apple build id, group assignment. No secret, OAuth value or token.
14. **Cleanup** (always), as in section 4.

The ASC client signs its ES256 token with the system `openssl` and converts the DER signature itself, so no Python package is installed on a runner that holds the key. Tokens last 15 minutes (Apple allows 20) and are made per request.

## 6. Architecture gate

- **Responsibilities.** The workflow orders stages and maps secrets to steps. `testflight_guard.py` owns credential-free source rules. `testflight_asc.py` owns App Store Connect calls and their read-backs. `testflight_verify_ipa.py` owns artefact checks. Each script is a pure core with a thin command-line shell.
- **Dependency direction.** Scripts depend only on the Python standard library and macOS tools (`openssl`, `codesign`, `security`). The workflow depends on the scripts; nothing in the app or packages depends on any of this. No app code, contract or persisted format changes.
- **Invariants.** Internal group only; one upload per build number; no re-runs; no secret in logs, arguments, artefacts or Git; HealthKit stays read-only (no entitlement or authorisation change); release identity fixed in reviewed source.
- **Extension axes.** A later tag trigger, a committed build number or a tester-set freeze can each be added to the guard or the preflight without changing the other stages.
- **Contract tests.** `test_testflight_release.py` covers DER conversion, an ES256 round trip with a throwaway key, pagination and host confinement, preflight refusals (used build, external group, public link, other app, malformed identity), processing failure, duplicates and timeout, read-back mismatches, encryption refusal, error messages without the token, dispatch rules (push, PR, branch, tag, fork, re-run, short SHA), build-number forms, version uniqueness, CI status on the exact SHA, What to Test extraction and path confinement, single-line outputs, and every IPA check, including that failures never echo OAuth values.

## 7. Threat model

| Threat | Mitigation | Residual |
| --- | --- | --- |
| Secret printed in a public log | No tracing, no dumps, secrets only in step `env:`, fixed error text, masking as backstop | A future edit could add an `echo`; review every change to this workflow as security-sensitive |
| Malicious pull request or fork reads secrets | No PR or fork triggers; environment limited to `main`; owner approval per run | None known |
| Workflow edited on a branch to exfiltrate | Deployment-branch policy `main`; `main` is protected by review and required checks | An admin merging an unreviewed change |
| Compromised third-party action | Only `actions/checkout`, pinned by SHA, without persisted credentials | Trust in GitHub's own action at that SHA |
| Input injection (`build_number`, What to Test) | Inputs only via `env:`, validated by pattern, text written to a file and sent as JSON | None known |
| Re-run uploads twice or reuses stale guard results | `run_attempt == 1` at job and step level; ASC preflight refuses a used build number | None known |
| Artefact or cache leaks the IPA or keys | No artefacts or caches; cleanup with `if: always()`; GitHub-hosted runners are discarded after the job | Apple's processing copy is the intended destination |
| Stolen API key used elsewhere | Key only in the environment; App Manager role, not Admin | A team key cannot be limited to one app, so it keeps App Manager access to every app in the team; rotate on any doubt |
| Stolen distribution identity | Dedicated CI certificate, revocable without touching the local Mac's | Until revoked, it can sign App Store builds for the team |
| Owner's GitHub account compromised | Two-factor authentication; approval required even for admins | The approver and the dispatcher are the same person |
| Accidental external release | Group check refuses non-internal groups and public links; no external API calls exist in the client | None known |

## 8. Owner setup, from the owner's own terminal

Run these yourself; an agent must not. Each `gh secret set` either prompts for a hidden value or reads stdin, so no value lands in shell history, process arguments or the screen. Replace `<id>` with your key id and the `.p12` and profile paths with yours.

Create the environment, its reviewer and its branch rule:

```bash
REPO=syamaner/WeeklyHealthReport

gh api -X PUT "repos/$REPO/environments/testflight" --input - <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "can_admins_bypass": false,
  "reviewers": [{ "type": "User", "id": 13239417 }],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON

gh api -X POST "repos/$REPO/environments/testflight/deployment-branch-policies" \
  -f name=main -f type=branch
```

(`13239417` is the numeric id of `syamaner`, from `gh api users/syamaner --jq .id`.)

Set the secrets, scoped to the environment:

```bash
REPO=syamaner/WeeklyHealthReport

gh secret set ASC_KEY_ID    --env testflight --repo "$REPO"    # prompts; paste the key id
gh secret set ASC_ISSUER_ID --env testflight --repo "$REPO"    # prompts; paste the issuer id
gh secret set ASC_PRIVATE_KEY --env testflight --repo "$REPO" \
  < ~/.appstoreconnect/private_keys/AuthKey_<id>.p8

sed -n 's/^GOOGLE_OAUTH_CLIENT_ID = //p' Config/DriveOAuth.local.xcconfig | tr -d '\n' \
  | gh secret set DRIVE_OAUTH_CLIENT_ID --env testflight --repo "$REPO"
sed -n 's/^GOOGLE_OAUTH_REDIRECT_SCHEME = //p' Config/DriveOAuth.local.xcconfig | tr -d '\n' \
  | gh secret set DRIVE_OAUTH_REDIRECT_SCHEME --env testflight --repo "$REPO"

base64 -i ~/secure/WeeklyHealthReport-CI-Distribution.p12 | tr -d '\n' \
  | gh secret set DIST_P12_B64 --env testflight --repo "$REPO"
gh secret set DIST_P12_PASSWORD --env testflight --repo "$REPO"  # prompts; paste the .p12 password
base64 -i ~/secure/WeeklyHealthReport_CI_App_Store.mobileprovision | tr -d '\n' \
  | gh secret set DIST_PROFILE_B64 --env testflight --repo "$REPO"
```

Run the two `sed` lines from the repository root, where your git-ignored `Config/DriveOAuth.local.xcconfig` lives. After setting them, delete the exported `.p12` from disk or keep it only in your password manager.

Read back names and protection (values are never returned):

```bash
gh secret list --env testflight --repo "$REPO"
gh api "repos/$REPO/environments/testflight" \
  --jq '{can_admins_bypass, rules: [.protection_rules[] | {type, reviewers: [.reviewers[]?.reviewer.login]}], branch_policy: .deployment_branch_policy}'
gh api "repos/$REPO/environments/testflight/deployment-branch-policies" --jq '[.branch_policies[] | {name, type}]'
```

Then, once this change is merged, dispatch a dry run (the default) and approve it:

```bash
gh workflow run testflight-release.yml --repo "$REPO" --ref main \
  -f build_number=26 -f release_doc=docs/releases/<next-release-record>.md
```

Revocation, if anything looks wrong: revoke the API key in App Store Connect (Users and Access, Integrations), revoke the CI certificate in the developer portal, then `gh secret delete <NAME> --env testflight --repo "$REPO"` for each secret.

## 9. Decisions for the owner

1. **Trigger.** Use manual `workflow_dispatch` on `main` for v1 instead of issue #85's immutable `testflight/*` tag contract? Recommendation: yes for v1; it gives the same one-approval, one-upload control with less setup, and a tag ruleset can be added later as an extra guard.
2. **Signing route.** Imported identity (`.p12` and profile as environment secrets) rather than cloud-managed signing? Recommendation: imported identity; cloud signing would need the key widened to Admin and lets Apple change signing assets mid-run.
3. **Certificate.** Create a dedicated Apple Distribution certificate and App Store profile for CI rather than exporting the local Mac's identity? Recommendation: dedicated, so either can be revoked alone.
4. **API key role.** Keep the existing App Manager key rather than creating a narrower or broader one? Recommendation: keep App Manager; it is the least role that uploads and manages TestFlight, and record that a team key reaches every app in the team.
5. **Gate on CI.** Require a successful `iOS CI` push run on the exact SHA instead of re-running the gates inside the release? Recommendation: require it; re-running costs about 20 macOS minutes and proves nothing new for the same SHA.
6. **Build number.** Pass the build number as a dispatch input at archive time, as for 0.2.0, rather than committing it to the project first? Recommendation: input for v1, with the preflight refusing any used number; revisit if a committed number is wanted for reproducibility.
7. **What to Test.** Read it from the reviewed release record (`release_doc`) by default rather than typing it at dispatch? Recommendation: release record, so the text is reviewed in Git like the 0.2.0 notes.
8. **First run.** Make the first dispatch a dry run (no upload) to prove signing and export on the runner? Recommendation: yes; `dry_run` defaults to on for that reason.
9. **Environment protection.** Owner as sole required reviewer, self-review allowed, administrator bypass off, `main` only? Recommendation: yes, as in section 8.
10. **Xcode version.** Use the `macos-26` image's default Xcode for the first dry run, then pin it with `xcode-select` once it is proven? Recommendation: yes; record the version from the job summary in the release record.
11. **Issue #85 scope.** Update the issue so v1 is this design, and move the stricter items it does not yet cover (tag rulesets, frozen tester set, privacy-manifest inventory, export-compliance allowlist) to a follow-up? Recommendation: yes, so the issue does not claim guarantees v1 does not enforce.
