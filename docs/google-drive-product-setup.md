# Product Google Drive export setup

This document covers the production `WeeklyHealthReport` target only. It does not
change or reuse the accepted synthetic harness configuration. The checked-in app
contains deliberately non-working OAuth placeholders and fails closed until its own
native iOS client is configured locally.

## Boundary

Use the already owner-approved Google Cloud project only after obtaining fresh
authority for the provider action. Create one native **iOS** OAuth client whose
bundle identifier exactly matches `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER`. Enable
only the Drive and Picker APIs already justified by the accepted flow and keep the
grant at exactly:

```text
https://www.googleapis.com/auth/drive.file
```

Do not create or store a client secret. Do not add an API key, web OAuth client,
hosted origin, backend, analytics, broader Drive scope or identity scope. If Google
requires any of those, stop and review the product boundary first.

## Local configuration

Copy the checked-in example:

```sh
cp Config/DriveOAuth.local.xcconfig.example Config/DriveOAuth.local.xcconfig
```

Set the native client ID and its reversed redirect scheme in the local file. The
redirect scheme must be the client ID stem prefixed with
`com.googleusercontent.apps.`. `DriveOAuth.local.xcconfig` is ignored by Git.
Before publication, confirm the real client ID, redirect scheme, account addresses,
Drive IDs and tokens are absent from the diff.

## Manual flow and evidence

The Daily JSON Export feature performs no automatic session restore, daily-snapshot
refresh or Drive export when its screen opens. The app's existing weekly report may
still refresh HealthKit as before. For export, the person must separately:

1. connect or explicitly restore a stored session;
2. create or select and validate a destination;
3. refresh a fresh on-device daily snapshot;
4. review its report date, cutoff and exact JSON; and
5. export that reviewed preview.

The app reports success only after reading back the expected account, parent, file
ID, app metadata and byte-for-byte content. It updates by the stored file ID and
does not delete first. Uncertain requests are reconciled, one active write is
serialised, cancellation before submission is safe, cancellation after submission
finishes reconciliation, and no automatic retry/offline queue exists.

Keep evidence separate:

- **Local:** source review, invented mock tests, simulator suite and static analysis.
- **Device:** product UI, Keychain relaunch, Health permission and representative
  Apple Health comparisons on an explicitly authorised physical iPhone.
- **Google:** exact account/client/scope, destination and independent Drive-web
  confirmation of same-ID replacement and content.

Local or simulator success does not prove device HealthKit behaviour or Google Drive
behaviour. `drive.file` visibility also does not prove a folder is empty. Recovery
must use an explicitly selected canonical JSON file and fails closed when account,
folder, installation marker, metadata or bytes are ambiguous.
