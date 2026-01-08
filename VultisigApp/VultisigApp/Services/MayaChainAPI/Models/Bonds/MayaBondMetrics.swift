//
//  MayaBondMetrics.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

/// Metrics calculated for a Maya bond position
struct MayaBondMetrics {
    let myBond: Decimal
    let myAward: Decimal
    let apr: Double
    let nodeStatus: String
}

/// Network-wide Maya bond information
struct MayaNetworkBondInfo {
    let apr: Double
    let nextChurnDate: Date?
}

/// Reason why bonding is not allowed
enum MayaBondIneligibilityReason {
    case notWhitelisted
    case nodeAtCapacity

    var localizedMessage: String {
        switch self {
        case .notWhitelisted:
            return "notWhitelistedOnNode".localized
        case .nodeAtCapacity:
            return "nodeAtMaxCapacity".localized
        }
    }
}

/// Result of bond eligibility check
struct MayaBondEligibility {
    let canBond: Bool
    let reason: MayaBondIneligibilityReason?
    let nodeStatus: String
    let currentProviders: Int

    var errorMessage: String? {
        reason?.localizedMessage
    }
}

/// Node status for unbonding eligibility
struct MayaNodeUnbondStatus {
    let nodeStatus: String
    let canUnbond: Bool

    var warningMessage: String? {
        if !canUnbond {
            return String(format: "nodeActiveCannotUnbond".localized, nodeStatus)
        }
        return nil
    }
}
