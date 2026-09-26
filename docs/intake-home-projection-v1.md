# Intake home and Food Log projection v1

Architecture gate: domain calculates a read-only nutrient total from plain confirmed contributions, application selects one non-superseded log version per item and resolves pinned nutrition references, and presentation formats the projection. The composition root supplies local storage. No HealthKit query, schema mutation, network call or daily-health export semantics change.

The home represents today's local food-log reporting date, explicitly “so far”; historical Food Log uses the selected stored reporting date. These are food-ledger projections, separate from completed-day HealthKit reports. No medical targets or zero-as-no-data states.

Version `food-intake-summary-v1`: scale each resolution by consumed quantity divided by its explicit basis quantity only when units agree. Never infer mass/volume density or portion weight. Exact measured/augmented values can contribute to totals; bounds, unknown nutrients, missing resolutions, mixtures, unsupported bases and incompatible units mark the affected total incomplete. Preserve a labelled known subtotal; never present it as a full intake total. Empty days show No data. Overflow fails closed as unknown.

Superseded log versions do not contribute. Competing current heads stop the projection rather than choosing by ordinal/time. Mixtures stop aggregation until an explicit component/double-counting contract exists. Source records and raw evidence remain unchanged. UI links retain existing search, barcode, lists, favourites, receipt, nutrition-review and export routes; no OCR control is introduced.

Contract checks: quantity scaling, missing-value contribution, empty-day state, mass/volume mismatch, bounds and overflow; version-head selection must reject conflicting heads. Simulator and static analysis prove software behaviour only.

## Local delivery evidence — 26 September 2026

The Today home, dated Food Log, quantity-corrected entry review and existing capture/export/report links are implemented locally. All 162 package tests pass; complete iPhone 17 Pro simulator tests, static analysis, dependency boundaries and diff checks pass. Full-page report capture is restricted to the visible health-report destination so Today/Food Log cannot generate an unrelated report PDF. The empty-state Today screen was visually inspected after a normal simulator launch. Populated totals, version heads, date correction and unsupported values have synthetic contract evidence; physical-device usability remains unverified. No commit, PR, merge or release has been made.
