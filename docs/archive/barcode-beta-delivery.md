# Barcode entry in the two-route beta

Issue: [#129](https://github.com/syamaner/WeeklyHealthReport/issues/129).

The main report exposes **Food logging → Scan Food Barcode** alongside generic
search and pasted lists. The user explicitly starts a scan. Unsupported devices
receive an available generic-search route; no unsupported scanner controller is
presented. Camera denial and runtime unavailability have distinct guidance. The
adapter checks device support, resolves camera permission, then checks runtime
availability, following [Apple's availability contract](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller/isavailable).

The existing barcode classifier and personal-library coordinator remain the
identity authority. An exact local match offers the shared confirmation screen;
it does not save automatically. A miss, malformed code, ambiguous or weak match,
or a failed local lookup retains the original barcode and offers generic search.
The search request carries this evidence alongside the typed query. Both remain
attached to candidate decisions and saved product versions, including exact-name
saved-food reuse. Search failure and no-result states keep the input available.
Selecting a generic candidate does not create an exact barcode-library alias.

The beta no longer offers label photography in barcode permission or fallback
guidance. That capability remains deferred under #93. Camera usage copy describes
only the shipped barcode action.

## Architecture and validation

The app root composes the VisionKit adapter, local library and existing
coordinator. A small presentation model owns capture state; attempt generations
discard late completion after cancellation. The scanner is cancelled when its
sheet disappears, and a new controller is created for each explicit attempt.
No classifier, persistence or nutrition rule is duplicated in the view.

Fake-scanner tests exercise denied/unavailable permission, malformed/missing local
matches, runtime failure, retry, overlapping attempts, task cancellation and late
completion. CoFID/store tests prove that barcode and query evidence survive
confirmation and save without inventing barcode identity. The report navigation
route is covered by the simulator suite. Package boundaries, frozen matching
evaluation, Xcode analysis and CI remain delivery gates.

The user has deferred physical-camera validation. Simulator and fake-scanner
results do not establish camera recognition quality or permission behaviour on a
physical device. No live camera, provider, Drive or personal HealthKit access is
needed for this software delivery.
