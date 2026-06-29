//
//  PromoBannerDismissalMigration.swift
//  VultisigApp
//

import Foundation
import SwiftData

/// Seeds the global `PromoBannerDismissalStore` from the two legacy permanent
/// dismissal stores so upgraders are not re-spammed:
///
/// - `appClosedBanners` (app-wide `UserDefaults`, JSON-encoded `[String]`) held
///   the `followVultisig` dismissal.
/// - `Vault.closedBanners` (per-vault SwiftData) held `upgradeVault` / `buyVult`
///   (and the now-session-scoped `backupVault`).
///
/// Each TTL banner present in any legacy source is seeded with
/// `dismissedAt = now`, so its TTL countdown restarts at upgrade time rather
/// than firing immediately. The per-vault data is collapsed to global storage
/// with OR-semantics (dismissed in any vault ⇒ globally dismissed) — the
/// alternative re-spams multi-vault users. `backupVault` is intentionally not
/// carried: it is now a session-scoped banner and should resurface once after
/// upgrade while the vault is still un-backed-up.
///
/// Idempotency comes from `AppMigrationService` (Keychain-versioned, runs once)
/// and is reinforced by the store's seed-if-absent semantics.
struct PromoBannerDismissalMigration: @MainActor AppMigration {
    let version: Int = 2

    let description: String = "Seeding global promo-banner dismissals from legacy per-vault/app-wide storage"

    private let store: PromoBannerDismissalStoring
    private let defaults: UserDefaults

    init(
        store: PromoBannerDismissalStoring = PromoBannerDismissalStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
    }

    @MainActor
    func migrate() throws {
        let legacyAppBanners = readLegacyAppBanners()
        let legacyVaultBanners = readLegacyVaultBanners()

        store.migrateLegacyDismissals(
            legacyAppBanners: legacyAppBanners,
            legacyVaultBanners: legacyVaultBanners,
            now: Date()
        )
    }

    /// `appClosedBanners` was written via `@AppStorage` over the retroactive
    /// `Array: RawRepresentable` conformance, i.e. a JSON string under the key.
    private func readLegacyAppBanners() -> [String] {
        guard let raw = defaults.string(forKey: "appClosedBanners"),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    @MainActor
    private func readLegacyVaultBanners() -> [String] {
        guard let modelContext = Storage.shared.modelContext else {
            return []
        }
        let descriptor = FetchDescriptor<Vault>()
        guard let vaults = try? modelContext.fetch(descriptor) else {
            return []
        }
        var union = Set<String>()
        for vault in vaults {
            union.formUnion(vault.closedBanners)
        }
        return Array(union)
    }
}
