//
//  TronResourcesLoader.swift
//  VultisigApp
//
//  Shared loader for TRON Bandwidth & Energy resources.
//

import Foundation
import OSLog

final class TronResourcesLoader: ObservableObject {
    @Published var availableBandwidth: Int64 = 0
    @Published var totalBandwidth: Int64 = 0
    @Published var availableEnergy: Int64 = 0
    @Published var totalEnergy: Int64 = 0
    @Published var isLoading: Bool = false

    private let address: String
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tron-resources")

    init(address: String) {
        self.address = address
    }

    @MainActor
    func load(forceRefresh: Bool = false) {
        let address = self.address
        Task {
            // Serve fresh-cached resources without a spinner; only show
            // loading when the cache is cold/stale or a refresh was forced.
            let cached = forceRefresh ? nil : await TronService.shared.cachedAccountResource(for: address)
            if let cached {
                apply(cached)
                return
            }

            isLoading = true
            defer { self.isLoading = false }

            do {
                let resource = try await TronService.shared.getAccountResource(address: address, forceRefresh: forceRefresh)
                apply(resource)
            } catch {
                logger.error("Failed to load Tron resources: \(error)")
            }
        }
    }

    @MainActor
    private func apply(_ resource: TronAccountResourceResponse) {
        availableBandwidth = resource.calculateAvailableBandwidth()
        totalBandwidth = resource.freeNetLimit + resource.NetLimit
        availableEnergy = resource.EnergyLimit - resource.EnergyUsed
        totalEnergy = resource.EnergyLimit
    }
}
