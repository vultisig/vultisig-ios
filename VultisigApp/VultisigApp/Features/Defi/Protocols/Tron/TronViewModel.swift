//
//  TronViewModel.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation

// MARK: - Resource Type
enum TronResourceType: String, CaseIterable, Identifiable {
    case bandwidth = "BANDWIDTH"
    case energy = "ENERGY"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bandwidth:
            return NSLocalizedString("tronResourceBandwidth", comment: "Bandwidth")
        case .energy:
            return NSLocalizedString("tronResourceEnergy", comment: "Energy")
        }
    }
    
    /// Returns the resource string for TRON protocol (FreezeBalanceV2/UnfreezeBalanceV2)
    var tronResourceString: String {
        return rawValue  // "BANDWIDTH" or "ENERGY"
    }
}

// MARK: - View Model (State Only)
final class TronViewModel: ObservableObject, Hashable, Equatable {
    static func == (lhs: TronViewModel, rhs: TronViewModel) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    private let id = UUID()
    @Published var isLoading = false
    @Published var error: Error?
    @Published var missingTrx = false
    
    // Balances
    @Published var availableBalance: Decimal = .zero
    @Published var frozenBandwidthBalance: Decimal = .zero
    @Published var frozenEnergyBalance: Decimal = .zero
    
    // Resources
    @Published var availableBandwidth: Int64 = 0
    @Published var totalBandwidth: Int64 = 0
    @Published var availableEnergy: Int64 = 0
    @Published var totalEnergy: Int64 = 0
    
    // Navigation
    @Published var showFreeze = false
    @Published var showUnfreeze = false
    
    let logic = TronViewLogic()
    
    var totalFrozenBalance: Decimal {
        frozenBandwidthBalance + frozenEnergyBalance
    }
}
