//
//  FastVaultEligibilityRefresher.swift
//  VultisigApp
//
//  Session-only confirmation, bounded refreshes and action-time presence lookup.

import Foundation
import SwiftData

@MainActor
final class FastVaultEligibilityRefresher {

    static let shared = FastVaultEligibilityRefresher()

    private struct Flight {
        let id: UUID
        let topology: FastVaultTopology
        let task: Task<FastVaultPresence, Never>
        var consumers: Set<UUID>
    }

    private var flights: [ObjectIdentifier: Flight] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var sweep: Task<Void, Never>?
    private var sweepCandidates: [ObjectIdentifier: (vault: Vault, context: ModelContext?)] = [:]
    private var sweepCurrentKey: ObjectIdentifier?
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

    func resolvePresence(_ vault: Vault) async -> FastVaultPresence {
        guard vault.hasServerSigner else { return .absent }
        let key = ObjectIdentifier(vault)
        let topology = FastVaultTopology(vault)
        let task: Task<FastVaultPresence, Never>
        let consumer = UUID()
        let flightID: UUID
        if var flight = flights[key], flight.topology == topology, !flight.task.isCancelled {
            flight.consumers.insert(consumer)
            flights[key] = flight
            task = flight.task
            flightID = flight.id
        } else {
            flights[key]?.task.cancel()
            let id = UUID()
            flightID = id
            let context = vault.modelContext
            task = Task { @MainActor in
                await acquireRequestSlot()
                defer {
                    releaseRequestSlot()
                    if flights[key]?.id == id { flights[key] = nil }
                }
                // A saved deletion invalidates model properties; establish membership
                // before reading topology or handing the model to the lookup.
                guard flights[key]?.id == id,
                      context == nil || context?.fetchAllVaults().contains(where: { $0 === vault }) == true,
                      FastVaultTopology(vault) == topology else {
                    return .unknown(.requestFailed)
                }
                let checked: FastVaultPresence = Task.isCancelled ? .unknown(.cancelled) : await checkEligibility(vault)
                let outcome: FastVaultPresence = Task.isCancelled ? .unknown(.cancelled) : checked
                guard flights[key]?.id == id,
                      context == nil || context?.fetchAllVaults().contains(where: { $0 === vault }) == true,
                      FastVaultTopology(vault) == topology else {
                    return .unknown(.requestFailed)
                }
                vault.fastVaultPresenceOutcome = outcome
                switch outcome {
                case .present, .absent:
                    vault.fastVaultEligibility = outcome == .present
                    vault.fastVaultEligibilityCheckedAt = now()
                    vault.fastVaultCheckedTopology = topology
                    saveStorage()
                case .unknown:
                    break
                }
                return outcome
            }
            flights[key] = Flight(id: id, topology: topology, task: task, consumers: [consumer])
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in
                cancelConsumer(consumer, key: key, flightID: flightID)
            }
        }
        return Task.isCancelled ? .unknown(.cancelled) : result
    }

    private func cancelConsumer(_ consumer: UUID, key: ObjectIdentifier, flightID: UUID) {
        guard var flight = flights[key], flight.id == flightID else { return }
        flight.consumers.remove(consumer)
        if flight.consumers.isEmpty { flight.task.cancel() }
        flights[key] = flight
    }

    /// One sequential coalesced sweep leaves a slot available for selection or
    /// action-time lookups. Across all callers, at most two lookups run at once.
    func refreshAllIfStale(_ vaults: [Vault]) async {
        for vault in vaults where vault.hasServerSigner {
            let key = ObjectIdentifier(vault)
            if key != sweepCurrentKey {
                sweepCandidates[key] = (vault, vault.modelContext)
            }
        }
        if let sweep {
            await sweep.value
            return
        }
        let task = Task { @MainActor in
            defer {
                sweep = nil
                sweepCurrentKey = nil
                sweepCandidates.removeAll()
            }
            while let (key, candidate) = sweepCandidates.first {
                sweepCandidates[key] = nil
                sweepCurrentKey = key
                guard !Task.isCancelled else { break }
                if let context = candidate.context,
                   !context.fetchAllVaults().contains(where: { $0 === candidate.vault }) {
                    continue
                }
                await refreshIfStale(candidate.vault)
                sweepCurrentKey = nil
            }
        }
        sweep = task
        await task.value
    }

    private func acquireRequestSlot() async {
        if activeRequests < 2 {
            activeRequests += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func releaseRequestSlot() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().resume()
        }
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
