//
//  FastVaultEligibilityRefresher.swift
//  VultisigApp
//
//  Session-only confirmation and shared background presence lookups.

import Foundation
import SwiftData

@MainActor
final class FastVaultEligibilityRefresher {

    static let shared = FastVaultEligibilityRefresher()

    private struct Flight {
        let id: UUID
        let topology: FastVaultTopology
        let task: Task<FastVaultPresence, Never>
    }

    private var flights: [ObjectIdentifier: Flight] = [:]
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
        _ = await resolvePresence(vault)
    }

    /// Routing uses a short confirmation window, independent of the daily
    /// lifecycle refresh. Unknown attempts and changed topology invalidate it.
    func confirmedPresenceForRouting(_ vault: Vault) -> FastVaultPresence? {
        guard vault.hasServerSigner else { return .absent }
        guard vault.fastVaultCheckedTopology == FastVaultTopology(vault),
              vault.fastVaultPresenceOutcome?.isUnknown == false,
              let checkedAt = vault.fastVaultEligibilityCheckedAt else { return nil }
        let age = now().timeIntervalSince(checkedAt)
        guard age >= 0, age < 60 else { return nil }
        return vault.fastVaultEligibility ? .present : .absent
    }

    /// Reuses completed background work or joins the same in-flight request.
    func presenceForRouting(_ vault: Vault) async -> FastVaultPresence {
        if let confirmed = confirmedPresenceForRouting(vault) { return confirmed }
        return await resolvePresence(vault)
    }

    /// The service owns the lookup. A departing caller stops using its result,
    /// but other callers and the cache can still benefit from its completion.
    func resolvePresence(_ vault: Vault) async -> FastVaultPresence {
        guard !Task.isCancelled else { return .unknown(.cancelled) }
        guard vault.hasServerSigner else { return .absent }
        let key = ObjectIdentifier(vault)
        let topology = FastVaultTopology(vault)
        let task: Task<FastVaultPresence, Never>
        if let flight = flights[key], flight.topology == topology {
            task = flight.task
        } else {
            flights[key]?.task.cancel()
            let id = UUID()
            let context = vault.modelContext
            task = Task { @MainActor in
                defer { if flights[key]?.id == id { flights[key] = nil } }
                // Saved deletion invalidates model properties. Check membership
                // before reading the model, both before and after the lookup.
                guard flights[key]?.id == id,
                      context == nil || context?.fetchAllVaults().contains(where: { $0 === vault }) == true,
                      FastVaultTopology(vault) == topology else {
                    return .unknown(.requestFailed)
                }
                let outcome = await checkEligibility(vault)
                guard !Task.isCancelled,
                      flights[key]?.id == id,
                      context == nil || context?.fetchAllVaults().contains(where: { $0 === vault }) == true,
                      FastVaultTopology(vault) == topology else {
                    return .unknown(.requestFailed)
                }
                vault.fastVaultPresenceOutcome = outcome
                if !outcome.isUnknown {
                    vault.fastVaultEligibility = outcome == .present
                    vault.fastVaultEligibilityCheckedAt = now()
                    vault.fastVaultCheckedTopology = topology
                    saveStorage()
                }
                return outcome
            }
            flights[key] = Flight(id: id, topology: topology, task: task)
        }
        let result = await task.value
        return Task.isCancelled ? .unknown(.cancelled) : result
    }

    /// Unknown and changed-topology results retry on each lifecycle trigger.
    /// Confirmed results retain the background freshness threshold.
    func refreshIfStale(_ vault: Vault) async {
        if vault.fastVaultCheckedTopology == nil || vault.fastVaultCheckedTopology == FastVaultTopology(vault),
           vault.fastVaultPresenceOutcome?.isUnknown != true,
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
