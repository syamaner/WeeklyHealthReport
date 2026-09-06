# Google Cloud and test-account setup for the synthetic Drive harness

This runbook reproduces the external configuration used for slice A without
publishing the Google Cloud project, account addresses, OAuth client ID, Drive IDs
or tokens. It applies only to `Tools/SyntheticDriveExport`, build 4, with bundle ID
`com.syamaner.WHRSyntheticDriveExport`. It does not authorise slice B, HealthKit
access or JSON export.

The native iOS app is a public OAuth client. **Do not request, download, create,
paste or store a client secret.** This flow also needs no API key, web OAuth client,
hosted Picker page, backend or authorised JavaScript origin.

## 1. Select and verify the private project

1. Sign in to [Google Cloud Console](https://console.cloud.google.com/) with the
   owner of the user-owned project already chosen for this work.
2. Use the project selector to select that exact project. Privately compare its
   name, project ID and project number with the owner's record before changing it.
3. Keep those identifiers and every account address out of source, issues, pull
   requests, screenshots and shared test notes.

Do not create a replacement project or change IAM, billing, organisation policy or
project ownership as part of this procedure.

## 2. Enable only the two required APIs

In **APIs & Services → Library**, enable:

- **Google Drive API**
- **Google Picker API**

Then open **APIs & Services → Enabled APIs & services** and verify those two are
enabled. Do not enable another API for this harness. An API already enabled for an
unrelated owner-controlled workload is not evidence that this harness needs it and
must not be disabled without separate authority.

## 3. Configure Google Auth Platform

If the project has not been registered for OAuth, open **Google Auth Platform →
Overview**, select **Get started**, and complete the minimum registration:

- Use a clear synthetic-harness app name.
- Set the user-support and developer-contact addresses privately to owner-controlled
  mailboxes.
- Select **External** as the audience and leave publishing status as **Testing**.

Do not invent a homepage, privacy-policy URL or authorised domain for this private
test harness. Do not publish the app to Production or submit it for verification as
part of slice A.

In **Data Access**, add only:

```text
https://www.googleapis.com/auth/drive.file
```

Remove any accidentally added broad Drive, Drive readonly, metadata-wide, OpenID,
email or profile scope before testing. Google's special browser/mobile Picker flow
permits only `drive.file` and cannot combine it with other scopes. The consent screen
must describe per-file access, not whole-Drive access.

## 4. Create the iOS OAuth client

1. Open **Google Auth Platform → Clients → Create client**.
2. Select **iOS** as the application type.
3. Enter the exact bundle ID:

   ```text
   com.syamaner.WHRSyntheticDriveExport
   ```

4. Give the client a private, recognisable name. App Store ID and Apple Team ID are
   unnecessary for this directly installed synthetic build unless the console makes
   one mandatory in a future UI.
5. Create the client and privately record only its client ID and the displayed iOS
   URL scheme. Do not create or retain a client secret.

The redirect used by the harness is the iOS URL scheme followed by
`:/oauth2redirect`. For a client ID shaped like
`NUMBER-NAME.apps.googleusercontent.com`, the scheme is shaped like
`com.googleusercontent.apps.NUMBER-NAME`. Do not copy either real value into this
document, an issue, a commit or a pull request.

## 5. Add and invite test users

Adding a test user is an allowlist operation; Google does **not** send that person an
invitation or the app build.

1. Open **Google Auth Platform → Audience**.
2. Confirm **User type: External** and **Publishing status: Testing**.
3. Under **Test users**, choose **Add users**.
4. Enter an eligible Google Account address and save. Verify it appears in the list.
5. Separately tell the tester, through a private channel, which synthetic build to
   use and the bounded acceptance steps. Never send credentials or ask for their
   password, recovery code or multi-factor code.

A Gmail address is already a Google Account. A non-Gmail address must first be
registered as a Google Account and may still be blocked by Google Workspace service
availability or administrator policy. If Google reports that an address is not
associated with a Google Account or is ineligible, do not work around the restriction:
use another owner-approved eligible account or stop that account's test.

Testing status has important limits:

- At most 100 test users can be added, counted over the project's testing lifetime.
- A `drive.file` authorisation, including an issued refresh token, expires seven
  days after consent while the app remains in Testing. Reconnect and consent again;
  do not weaken token handling to avoid expiry.
- Test users can see an unverified-app warning. They should continue only after
  checking the app name, owner-approved account and exact `drive.file` permission.

For the two-account isolation check, add both eligible accounts before installing or
retesting. Keep their addresses only in the owner's private acceptance record.

## 6. Configure the local build without publishing identifiers

From the repository root, copy the checked-in example to the ignored local file:

```sh
cp Tools/SyntheticDriveExport/Config/OAuth.local.xcconfig.example \
  Tools/SyntheticDriveExport/Config/OAuth.local.xcconfig
```

Set these three values locally:

```text
GOOGLE_OAUTH_CLIENT_ID = <private iOS client ID>
GOOGLE_OAUTH_REDIRECT_SCHEME = <private iOS URL scheme>
SYNTHETIC_DRIVE_BUNDLE_IDENTIFIER = com.syamaner.WHRSyntheticDriveExport
```

`OAuth.local.xcconfig` is ignored by Git and overrides deliberately non-working
defaults. Before committing, confirm `git status --ignored` marks it ignored and
search the staged diff for the client ID, account addresses and Drive IDs. Tokens
belong only in the harness's this-device-only Keychain storage; they must never be
placed in an xcconfig file.

## 7. Tester procedure and evidence boundary

Install build 4 on an explicitly authorised device only. Ask the tester to:

1. Start consent, inspect the named account and permission, and cancel once to prove
   cancellation preserves no new connection or destination.
2. Complete **Create WeeklyHealthReport Exports**, confirm the exact `drive.file`
   grant, and privately verify the created folder in Drive web.
3. Prove secure restoration, local sign-out, remote revocation and a denied or
   expired credential. Local sign-out must not be described as Google revocation and
   neither action deletes the Drive folder.
4. Complete **Choose existing folder** with a fresh, dedicated synthetic folder. In
   the Picker, change the filter to **Folder** before selecting it. On the tested
   iPhone, scrolling could select the item under the finger, so scroll cautiously
   and cancel/retry if the wrong item is selected.
5. Switch to the second allowlisted account, establish its separate destination,
   then switch back and verify no account/destination binding crossed accounts.
6. Verify access is denied for one unrelated disposable synthetic file that was
   never selected or created by the app.

Record evidence in three separate groups:

- **Google:** project privately matched; only Drive and Picker APIs required by this
  harness; External/Testing; test users allowlisted; exact iOS client and scope.
- **Device:** build/device identity, consent/cancel, both destination flows, restore,
  sign-out, revoke/expiry, account switching and unrelated-file denial.
- **Local:** ignored configuration, exact bundle/redirect wiring, tests, build and
  analysis results, and a clean public diff.

Do not enumerate a selected folder's contents. Under `drive.file`, limited visibility
does not prove that a folder is empty. Folder emptiness, existence and file effects
must be checked independently by the owner in Drive web, without publishing IDs or
screenshots containing account details.

If the special Picker flow stops returning to the iOS client, asks for another scope,
or appears to require hosting, stop. Record the exact error and proposed requirement;
do not add a web client, API key, hosted origin, backend or broader permission.

## 8. Removing access after testing

- **Local sign-out** clears local credentials and destination state only.
- **Revoke Google access** revokes the grant and clears local state only after the
  remote revocation succeeds.
- Removing a person from **Audience → Test users** prevents a new testing grant but
  is not a substitute for revoking an existing grant.
- Deleting folders, OAuth clients or the Cloud project is outside this runbook and
  requires separate, exact authority.

## Official references checked 6 September 2026

- [Manage OAuth clients](https://support.google.com/cloud/answer/15549257?hl=en)
- [Manage the app audience and test users](https://support.google.com/cloud/answer/15549945?hl=en)
- [Set up OAuth 2.0 for an iOS application](https://support.google.com/googleapi/answer/6158849?hl=en)
- [OAuth 2.0 for native applications](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Browser/mobile Picker flow](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker)
- [When OAuth verification is not required](https://support.google.com/cloud/answer/13464323?hl=en)
