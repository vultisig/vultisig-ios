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
