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
