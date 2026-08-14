//
//  FunctionCallTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum FunctionCallType: String, CaseIterable, Identifiable {
    case
         rebond,
         leave,
         custom,
         vote,
         cosmosIBC,
         merge,
         unmerge,
         theSwitch,
         addThorLP,
         withdrawSecuredAsset

    var id: String { self.rawValue }

    func display() -> String {
        switch self {
        case .rebond:
            return NSLocalizedString("Rebond", comment: "")
        case .leave:
            return NSLocalizedString("Leave", comment: "")
        case .custom:
            return NSLocalizedString("Custom", comment: "")
        case .vote:
            return NSLocalizedString("Vote", comment: "")
        case .cosmosIBC:
            return NSLocalizedString("IBC Transfer", comment: "")
        case .merge:
            return NSLocalizedString("Merge", comment: "")
        case .unmerge:
            return NSLocalizedString("Withdraw RUJI", comment: "")
        case .theSwitch:
            return NSLocalizedString("Switch", comment: "")
        case .addThorLP:
            return NSLocalizedString("Add THORChain LP", comment: "")
        case .withdrawSecuredAsset:
            return NSLocalizedString("Withdraw Secured Asset", comment: "")
        }
    }

    static func getCases(for coin: Coin) -> [FunctionCallType] {
        switch coin.chain {
        case .thorChain:
            return [
                .rebond,
                .leave,
                .merge,
                .unmerge,
                .custom,
                .withdrawSecuredAsset
            ]

        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return [.addThorLP]
        case .mayaChain:
            return [.leave,
                    .custom]
        case .dydx:
            return [.vote]
        case .gaiaChain:
            return [
                .cosmosIBC,
                .theSwitch
            ]
        case .kujira, .osmosis:
            return [.cosmosIBC]

        case .thorChainChainnet, .thorChainStagenet:
            // The test networks offer the entry button but had no case list,
            // so the selector opened empty over whatever form the default
            // happened to build. Custom is the operation they support — the
            // same `MsgDeposit` mainnet takes — so naming it here makes the
            // button lead somewhere. `FunctionCallCustom` had to learn these
            // chains too, or the form it opens could never be submitted.
            return [.custom]

        default:
            return []
        }
    }

    /// The function the details screen opens on. Must always be a member of
    /// `getCases(for:)` — a default the dropdown does not list strands the
    /// user on a form they cannot get back to. `FunctionCallInstance.getDefault`
    /// builds the matching sub-model and has to agree case-for-case; neither
    /// factory derives from the other, so the pairing is pinned by tests.
    static func getDefault(for coin: Coin) -> FunctionCallType {
        switch coin.chain {
        case .thorChain:
            // Rebond and Leave have both moved to
            // `Features/FunctionTransaction/`, so the raw memo is the remaining
            // THORChain entry that still builds a form here — and it was
            // already the default for the TCY family.
            return .custom
        // Must stay inside `getCases(for:)` above — the screen opens on this
        // selection, and a default the dropdown does not offer strands the user
        // on a form they cannot get back to. MayaChain falls through to the
        // raw-memo operation for the same reason: LEAVE, the arm that used to
        // be here, has its own screen and builds no form for this one to open
        // on.
        case .dydx:
            return .vote
        case .gaiaChain:
            return .theSwitch
        case .kujira, .osmosis:
            return .cosmosIBC
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            // Add-LP is migrated and has no legacy form, but it is also the
            // only operation these chains still offer once SECURE+ mint retires
            // to Swap. Naming anything else here would name an operation the
            // chain does not have, so the honest answer is the migrated one —
            // and it costs nothing, because the action list passes a
            // single-operation chain straight through to that operation's own
            // screen without ever consulting a default.
            return .addThorLP
        default:
            return .custom
        }
    }
}
