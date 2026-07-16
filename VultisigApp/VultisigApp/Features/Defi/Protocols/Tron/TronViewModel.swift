//
//  TronViewModel.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation
import SwiftUI

// MARK: - Resource Type
enum TronResourceType: String, CaseIterable, FilledSegmentedControlType {
    case bandwidth = "BANDWIDTH"
    case energy = "ENERGY"

    var id: Int {
        switch self {
        case .bandwidth:
            return 0
        case .energy:
            return 1
        }
    }

    var title: String {
        displayName
    }

    var icon: String? {
        switch self {
        case .bandwidth:
            return "gauge-2"
        case .energy:
            return "bolt"
        }
    }

    var iconSelectedTint: Color? {
        switch self {
        case .bandwidth:
            return Theme.colors.alertSuccess
        case .energy:
            return Theme.colors.alertWarning
        }
    }

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

    @MainActor
    func apply(account: TronAccountResponse) {
        let balanceSun = account.balance ?? 0
        availableBalance = Decimal(balanceSun) / Decimal(1_000_000)

        frozenBandwidthBalance = Decimal(account.frozenBandwidthSun) / Decimal(1_000_000)
        frozenEnergyBalance = Decimal(account.frozenEnergySun) / Decimal(1_000_000)
        unfreezingBalance = Decimal(account.unfreezingTotalSun) / Decimal(1_000_000)

        pendingWithdrawals = (account.unfrozenV2 ?? []).compactMap { entry in
            guard let amountSun = entry.unfreeze_amount,
                  let expireTime = entry.unfreeze_expire_time else {
                return nil
            }

            let amountTrx = Decimal(amountSun) / Decimal(1_000_000)
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(expireTime / 1_000))
            return TronPendingWithdrawal(amount: amountTrx, expirationDate: expirationDate)
        }.sorted { $0.expirationDate < $1.expirationDate }

        isLoadingBalance = false
    }

    @MainActor
    func apply(resource: TronAccountResourceResponse) {
        availableBandwidth = resource.calculateAvailableBandwidth()
        totalBandwidth = resource.freeNetLimit + resource.NetLimit
        availableEnergy = resource.EnergyLimit - resource.EnergyUsed
        totalEnergy = resource.EnergyLimit
        isLoadingResources = false
    }
}
