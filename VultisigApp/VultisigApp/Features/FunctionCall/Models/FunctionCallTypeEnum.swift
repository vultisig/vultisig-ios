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
            // button lead somewhere. The form's asset predicate has to know
            // these chains too, or the form it opens could never be submitted.
            return [.custom]

        default:
            return []
        }
    }

    /// The function the details screen opens on. Must always be a member of
    /// `getCases(for:)` — a default the dropdown does not list strands the
    /// user on a form they cannot get back to. `FunctionCallInstance.getDefault`
    /// builds the matching sub-model and is derived from this answer, so the two
    /// can no longer name different operations; what a test still pins is that
    /// every value here is one `getCases(for:)` offers.
    static func getDefault(for coin: Coin) -> FunctionCallType {
        switch coin.chain {
        case .thorChain:
            // The same predicate the raw-memo form's own asset picker uses, so
            // the operation this routes a holder to can always offer the coin
            // it routed them for. Open-coded here as a case-sensitive
            // `contains("TCY")`, it disagreed with the form on both the
            // wrappers and their casing.
            if CustomMemoAssets.isTcyFamily(ticker: coin.ticker) {
                return .custom
            }
            return .rebond
        // MayaChain has no arm: its bond/unbond forms are gone and LEAVE has
        // its own screen, so the raw-memo fallthrough is the only operation it
        // could open on.
        case .dydx:
            return .vote
        case .gaiaChain:
            // Every Cosmos operation the Functions screen offers is now on
            // `Features/FunctionTransaction/`, so these defaults all name a
            // migrated type. That is the honest answer — it is what the chain
            // does — and it costs nothing: the action list carries each row's
            // own destination and never consults a default. What still has to
            // hold is that the default is something the chain offers, which
            // `FunctionCallReachabilityTests` pins.
            return .cosmosIBC
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
