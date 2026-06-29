//
//  PromoBannerDismissalStore.swift
//  VultisigApp
//

import Foundation

/// App-wide, per-device record of which promo banners the user has dismissed.
///
/// Keyed by the banner's stable `dismissalID` (intent), never by vault — so a
/// dismissal made on one vault is honored on every vault, and switching vaults
/// can never resurface a banner before its rule allows it.
///
/// Two backends, chosen per banner by `BannerDismissalRule`:
///
/// - **TTL banners** persist `dismissalID -> dismissedAt` as JSON in
///   `UserDefaults`. `isDismissed` is true while `now < dismissedAt + interval`.
/// - **Session banners** (the backup reminder) route into an in-memory set that
///   is never persisted. It starts empty every cold launch, so the banner
///   reappears on the next launch while it is still eligible. Hidden for the
///   rest of the current session so the many `setupBanners` re-runs
///   (pull-to-refresh, throttled appear, vault switch, currency change) don't
///   pop it straight back.
protocol PromoBannerDismissalStoring: AnyObject {
    func isDismissed(_ banner: VaultBannerType, now: Date) -> Bool
    func dismiss(_ banner: VaultBannerType, now: Date)
    /// Seeds the persistent store from legacy permanent dismissals so upgraders
    /// are not re-spammed. Idempotent: never overwrites an existing entry.
    func migrateLegacyDismissals(legacyAppBanners: [String], legacyVaultBanners: [String], now: Date)
}

final class PromoBannerDismissalStore: PromoBannerDismissalStoring, @unchecked Sendable {

    static let shared = PromoBannerDismissalStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    /// In-memory, process-scoped dismissals for `.session`-ruled banners. Never
    /// written to `defaults`, so it resets on every cold launch.
    private var sessionDismissed: Set<String> = []

    init(defaults: UserDefaults = .standard, storageKey: String = "promoBannerDismissals") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func isDismissed(_ banner: VaultBannerType, now: Date) -> Bool {
        switch banner.dismissalRule {
        case .session:
            lock.lock()
            defer { lock.unlock() }
            return sessionDismissed.contains(banner.dismissalID)
        case .ttl(let interval):
            guard let dismissedAt = persistentDismissals()[banner.dismissalID] else {
                return false
            }
            return now < dismissedAt.addingTimeInterval(interval)
        }
    }

    func dismiss(_ banner: VaultBannerType, now: Date) {
        switch banner.dismissalRule {
        case .session:
            lock.lock()
            sessionDismissed.insert(banner.dismissalID)
            lock.unlock()
        case .ttl:
            var dict = persistentDismissals()
            dict[banner.dismissalID] = now
            persist(dict)
        }
    }

    func migrateLegacyDismissals(legacyAppBanners: [String], legacyVaultBanners: [String], now: Date) {
        // Only TTL banners carry over. The backup reminder is session-scoped:
        // per product it should resurface each session while backup is missing,
        // so its legacy permanent dismissal is intentionally dropped.
        for banner in VaultBannerType.allCases {
            let legacySources: [String]
            switch banner {
            case .followVultisig:
                legacySources = legacyAppBanners
            case .upgradeVault, .buyVult:
                legacySources = legacyVaultBanners
            case .backupVault:
                continue
            }
            guard legacySources.contains(banner.rawValue) else { continue }
            seedDismissedIfAbsent(banner, now: now)
        }
    }

    // MARK: - Private

    /// Writes `dismissedAt = now` only if no entry exists yet, so re-running the
    /// migration never resets a countdown that already started.
    private func seedDismissedIfAbsent(_ banner: VaultBannerType, now: Date) {
        var dict = persistentDismissals()
        guard dict[banner.dismissalID] == nil else { return }
        dict[banner.dismissalID] = now
        persist(dict)
    }

    private func persistentDismissals() -> [String: Date] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ dict: [String: Date]) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(dict) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
