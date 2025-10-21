//
//  BondNode.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

struct BondNode: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let state: BondNodeState
}

enum BondNodeState: String, Codable, CaseIterable {
    case whitelisted
    case standby
    case ready
    case active
    case disabled
    case unknown

    /// Whether the node can be unbonded
    var canUnbond: Bool {
        switch self {
        case .whitelisted, .standby, .unknown:
            return true
        case .ready, .active, .disabled:
            return false
        }
    }

    /// Whether a user can bond to this node
    var canBond: Bool {
        switch self {
        case .whitelisted, .standby, .ready, .active:
            return true
        case .disabled, .unknown:
            return false
        }
    }

    /// Whether the node is currently earning rewards
    var isEarningRewards: Bool {
        self == .active
    }

    /// Initialize from API response status string
    init?(fromAPIStatus status: String) {
        let lowercased = status.lowercased()
        switch lowercased {
        case "whitelisted":
            self = .whitelisted
        case "standby":
            self = .standby
        case "ready":
            self = .ready
        case "active":
            self = .active
        case "disabled":
            self = .disabled
        default:
            self = .unknown
        }
    }
}
