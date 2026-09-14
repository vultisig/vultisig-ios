//
//  FastVaultEligibilityRefresher.swift
//  VultisigApp
//
//  Refreshes the cached `fastVaultEligibility` field on the `Vault` model.
//  Reads are sync (`vault.fastVaultEligibility`); refreshes happen only at
//  planned trigger points (app foreground, vault switch). Replaces the
//  pattern where every Send / FunctionCall / Referral / QBTC screen called
//  `FastVaultService.isEligibleForFastSign(vault:)` on mount.
//

import Foundation
import OSLog

@MainActor
final class FastVaultEligibilityRefresher {

    static let shared = FastVaultEligibilityRefresher()

    private let checkEligibility: @MainActor (Vault) async -> FastVaultPresence
    private let saveStorage: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let stalenessThreshold: TimeInterval

    nonisolated static let defaultStalenessThreshold: TimeInterval = 24 * 60 * 60  // 24h

    init(
        checkEligibility: @MainActor @escaping (Vault) async -> FastVaultPresence = { await FastVaultService.shared.presence(pubKeyECDSA: $0.pubKeyECDSA) },
        saveStorage: @MainActor @escaping () -> Void = FastVaultEligibilityRefresher.defaultSaveStorage,
        now: @MainActor @escaping () -> Date = { Date() },
        stalenessThreshold: TimeInterval = FastVaultEligibilityRefresher.defaultStalenessThreshold
    ) {
        self.checkEligibility = checkEligibility
        self.saveStorage = saveStorage
        self.now = now
        self.stalenessThreshold = stalenessThreshold
    }

    /// Unknown attempts never overwrite the last confirmed result or timestamp.
    func refresh(_ vault: Vault) async {
        guard vault.hasServerSigner else { return }
        let outcome = await checkEligibility(vault)
        vault.fastVaultPresenceOutcome = outcome
        switch outcome {
        case .present, .absent:
            vault.fastVaultEligibility = outcome == .present
            vault.fastVaultEligibilityCheckedAt = now()
            saveStorage()
        case .unknown:
            break
        }
    }

    /// Refreshes only if the cache is empty or older than `stalenessThreshold`.
    /// Use this on app foreground + vault switch — cheap when fresh, network
    /// hit on staleness.
    func refreshIfStale(_ vault: Vault) async {
        if vault.fastVaultPresenceOutcome?.isUnknown != true,
           let checkedAt = vault.fastVaultEligibilityCheckedAt,
           now().timeIntervalSince(checkedAt) < stalenessThreshold {
            return
        }
        await refresh(vault)
    }

    @MainActor
    private static func defaultSaveStorage() {
        do {
            try Storage.shared.save()
        } catch {
            // Logger inside instance; can't easily call from static. Fail silently —
            // the cache is best-effort; next refresh will overwrite.
        }
    }
}
