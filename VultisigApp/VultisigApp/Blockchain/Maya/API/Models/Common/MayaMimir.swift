//
//  MayaMimir.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation

struct MayaMimir: Codable {
    let cacaoPoolDepositMaturityBlocks: Int64
    let minimumBondInRune: Int64?
    let maxBondProviders: Int?
    let pauseBond: Int64?

    enum CodingKeys: String, CodingKey {
        case cacaoPoolDepositMaturityBlocks = "CACAOPOOLDEPOSITMATURITYBLOCKS"
        case minimumBondInRune = "MINIMUMBONDINRUNE"
        case maxBondProviders = "MAXBONDPROVIDERS"
        case pauseBond = "PAUSEBOND"
    }

    /// Minimum bond requirement in CACAO (converted from base units)
    var minimumBondCacao: Decimal {
        let minBond = Decimal(minimumBondInRune ?? 3500000000000000)
        return minBond / pow(10, 10)
    }

    /// Whether bonding is currently paused (0 = enabled, non-zero = paused)
    var isBondingPaused: Bool {
        (pauseBond ?? 0) != 0
    }

    /// Maximum number of bond providers allowed per node
    var maxProviders: Int {
        maxBondProviders ?? 8
    }
}
