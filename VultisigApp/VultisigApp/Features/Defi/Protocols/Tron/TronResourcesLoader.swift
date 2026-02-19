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
    func load() {
        isLoading = true

        Task {
            defer { self.isLoading = false }

            do {
                let resource = try await TronService.shared.getAccountResource(address: address)
                self.availableBandwidth = resource.calculateAvailableBandwidth()
                self.totalBandwidth = resource.freeNetLimit + resource.NetLimit
                self.availableEnergy = resource.EnergyLimit - resource.EnergyUsed
                self.totalEnergy = resource.EnergyLimit
            } catch {
                logger.error("Failed to load Tron resources: \(error)")
            }
        }
    }
}
