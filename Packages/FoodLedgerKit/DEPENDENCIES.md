# Dependency inventory

## GRDB.swift 7.11.1

- Source: <https://github.com/groue/GRDB.swift>
- Exact release: <https://github.com/groue/GRDB.swift/releases/tag/v7.11.1>
- Release date: 18 June 2026.
- Licence: MIT, copyright 2015-2025 Gwendal Roué. The upstream `LICENSE`
  notice must be retained with substantial copies.
- Reviewed package requirements: Swift tools 6.1, iOS 13 or later and macOS
  10.15 or later. This package requires iOS 17 and macOS 14, and the repository
  builds with Xcode 27 / Swift 6.4, so the reviewed release is compatible.
- Product used: `GRDB` only, and only from `FoodLedgerGRDB`.
- Purpose: typed SQLite access, migrations and serialized `DatabaseQueue`
  transactions. SQL records and database handles do not cross the adapter.

No SQLCipher product, provider SDK, networking library or UI framework is added.

## Optional Gemini BYOK discovery

No third-party provider SDK is linked. The existing infrastructure target uses
Foundation HTTPS and Apple's Security framework for a user-owned Keychain item;
presentation uses Apple's WebKit only for isolated Google Search suggestions.
The API route, model, retention and acceptance boundary are documented in
`../../docs/gemini-grounded-food-discovery-plan-v1.md`.

## SwiftSoup 2.13.9

- Source: <https://github.com/scinfu/SwiftSoup>.
- Exact package version: 2.13.9; resolved revision
  `18b80329749eca5ea29fc50211dca5c7eff5bfec` in both package lockfiles.
- Licence: MIT. The retained upstream notice is bundled at
  `Sources/FoodGenericSearch/Resources/SwiftSoup-LICENSE.txt`.
- Product used: `SwiftSoup`, only in `FoodGenericSearch` for the reviewed HTML
  table projector, manufacturer page identity and Alpro/Arla/Oatly adapters.
  Package boundaries prohibit exposing it to domain/application/presentation.
- Purpose: parse independently acquired source HTML; it does not fetch pages,
  provide model nutrition or override closed admission/basis/save rules.
- Compatibility evidence: the accumulated package and iOS simulator suites and
  Xcode static analysis passed using this exact resolved dependency (v72).

CoreFoundation is an Apple framework, restricted to the OFF transport to distinguish
JSON Boolean timeout flags from numeric values. It is not a provider dependency.
