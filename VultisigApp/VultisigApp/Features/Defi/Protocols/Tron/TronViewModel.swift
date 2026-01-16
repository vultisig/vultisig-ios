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

// MARK: - Pending Withdrawal (for unfreezing entries)
struct TronPendingWithdrawal: Identifiable {
    let id = UUID()
    let amount: Decimal  // In TRX
    let expirationDate: Date
    
    var isClaimable: Bool {
        Date() >= expirationDate
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
    @Published var isLoading = false  // General loading (for initial load)
    @Published var isLoadingBalance = false  // Loading frozen balance
    @Published var isLoadingResources = false  // Loading bandwidth/energy
    @Published var error: Error?
    @Published var missingTrx = false
    
    // Balances
    @Published var availableBalance: Decimal = .zero
    @Published var frozenBandwidthBalance: Decimal = .zero
    @Published var frozenEnergyBalance: Decimal = .zero
    @Published var unfreezingBalance: Decimal = .zero  // Total pending unfreeze
    @Published var pendingWithdrawals: [TronPendingWithdrawal] = []  // Individual entries
    
    // Resources
    @Published var availableBandwidth: Int64 = 0
    @Published var totalBandwidth: Int64 = 0
    @Published var availableEnergy: Int64 = 0
    @Published var totalEnergy: Int64 = 0
    
    // Navigation
    @Published var showFreeze = false
    @Published var showUnfreeze = false
    
    let logic = TronViewLogic()
    
    /// Total frozen + unfreezing balance
    var totalFrozenBalance: Decimal {
        frozenBandwidthBalance + frozenEnergyBalance + unfreezingBalance
    }
    
    /// Has pending withdrawals waiting
    var hasPendingWithdrawals: Bool {
        !pendingWithdrawals.isEmpty
    }
}
