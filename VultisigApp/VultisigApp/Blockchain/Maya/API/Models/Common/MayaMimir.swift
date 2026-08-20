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
    let haltChainGlobal: Int64?
    let nodePauseChainGlobal: Int64?
    let haltMayaChain: Int64?
    let solvencyHaltMayaChain: Int64?

    enum CodingKeys: String, CodingKey {
        case cacaoPoolDepositMaturityBlocks = "CACAOPOOLDEPOSITMATURITYBLOCKS"
        case minimumBondInRune = "MINIMUMBONDINRUNE"
        case maxBondProviders = "MAXBONDPROVIDERS"
        case pauseBond = "PAUSEBOND"
        case haltChainGlobal = "HALTCHAINGLOBAL"
        case nodePauseChainGlobal = "NODEPAUSECHAINGLOBAL"
        // MAYANode's native BASEChain identifier is MAYA.
        case haltMayaChain = "HALTMAYACHAIN"
        case solvencyHaltMayaChain = "SOLVENCYHALTMAYACHAIN"
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

    /// Mirrors MAYANode's `IsChainHalted(ctx, common.BASEChain)` decision for
    /// native `MsgDeposit`. Most halt Mimirs store the block height at which the
    /// halt begins; `NodePauseChainGlobal` instead stores the height through
    /// which a node-operator pause remains active.
    func isNativeDepositHalted(at currentHeight: Int64) -> Bool {
        Self.haltStarted(haltChainGlobal, at: currentHeight)
            || Self.nodePauseActive(nodePauseChainGlobal, at: currentHeight)
            || Self.haltStarted(haltMayaChain, at: currentHeight)
            || Self.haltStarted(solvencyHaltMayaChain, at: currentHeight)
    }

    private static func haltStarted(_ value: Int64?, at currentHeight: Int64) -> Bool {
        guard let value else { return false }
        return value > 0 && value < currentHeight
    }

    private static func nodePauseActive(_ value: Int64?, at currentHeight: Int64) -> Bool {
        guard let value else { return false }
        return value > currentHeight
    }
}
