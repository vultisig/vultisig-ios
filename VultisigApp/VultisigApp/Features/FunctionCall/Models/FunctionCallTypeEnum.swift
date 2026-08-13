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
         securedAsset,
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
            if coin.ticker.contains("TCY") {
                return .custom
            }
            return .rebond
        // Must stay inside `getCases(for:)` above — the screen opens on this
        // selection, and a default the dropdown does not offer strands the user
        // on a form they cannot get back to. MayaChain falls through to the
        // raw-memo operation: LEAVE, the arm that used to be here, has moved to
        // its own screen and builds no form for this one to open on.
        case .dydx:
            return .vote
        case .gaiaChain:
            return .theSwitch
        case .kujira, .osmosis:
            return .cosmosIBC
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            // Was `.addThorLP`, which now has its own screen and builds no
            // legacy form. A migrated type must never be a chain's default:
            // the default is applied without publishing a change, so the
            // route-out never fires and the user lands on a selection with
            // nothing behind it.
            return .securedAsset
        default:
            return .custom
        }
    }
}
