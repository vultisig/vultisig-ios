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
         bondMaya,
         unbondMaya,
         leave,
         custom,
         vote,
         cosmosIBC,
         merge,
         unmerge,
         theSwitch,
         addThorLP,
         securedAsset,
         withdrawSecuredAsset

    var id: String { self.rawValue }

    func display() -> String {
        switch self {
        case .rebond:
            return NSLocalizedString("Rebond", comment: "")
        case .bondMaya:
            return NSLocalizedString("Bond", comment: "")
        case .unbondMaya:
            return NSLocalizedString("Unbond", comment: "")
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
        case .securedAsset:
            return NSLocalizedString("Secured Assets", comment: "")
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
                .securedAsset,
                .withdrawSecuredAsset
            ]

        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return [
                .addThorLP,
                .securedAsset
            ]
        case .mayaChain:
            return [.bondMaya,
                    .unbondMaya,
                    .leave,
                    .custom]
        case .dydx:
            return [.vote]
        case .gaiaChain:
            return [
                .cosmosIBC,
                .theSwitch
            ]
        case .kujira:
            return [.cosmosIBC]
        case .osmosis:
            return [.cosmosIBC]
        case .noble:
            return [.cosmosIBC]
        case .akash:
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

    static func getDefault(for coin: Coin) -> FunctionCallType {
        switch coin.chain {
        case .thorChain:
            if coin.ticker.contains("TCY") {
                return .custom
            }
            return .rebond
        case .mayaChain:
            return .bondMaya
        case .dydx:
            return .vote
        case .gaiaChain:
            return .theSwitch
        // Kujira defaulted to `.cosmosIBC`, which has moved to
        // `Features/FunctionTransaction/` and no longer builds a legacy form.
        // It falls through to `.custom` instead — unreachable in practice,
        // since Kujira offers one operation and the action list passes straight
        // through to it, but a default that names a migrated type is what
        // `testNoChainDefaultsToAMigratedFunction` exists to catch.
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP
        default:
            return .custom
        }
    }
}
