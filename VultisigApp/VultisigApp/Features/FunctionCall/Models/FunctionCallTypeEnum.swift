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
            return NSLocalizedString("withdrawSecuredAsset", comment: "")
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

    /// The function the details screen opens on. Must be a member of
    /// `getCases(for:)` whenever the dropdown can still be entered — a
    /// default the dropdown does not list strands the user on a form they
    /// cannot get back to — except a chain whose every operation has been
    /// migrated, where the dropdown is unreachable and the default is
    /// vestigial (Gaia). `FunctionCallInstance.getDefault` builds the
    /// matching sub-model and has to agree case-for-case; neither factory
    /// derives from the other, so the pairing is pinned by tests.
    static func getDefault(for coin: Coin) -> FunctionCallType {
        switch coin.chain {
        case .thorChain:
            // Rebond and Leave have both moved to
            // `Features/FunctionTransaction/`, and the route-out that reaches
            // them fires on a *change* of selection — a migrated default would
            // open this screen on a function that builds no form at all.
            // Custom is the remaining THORChain entry that always builds one,
            // and was already the default for TCY.
            return .custom
        case .mayaChain:
            return .custom
        case .dydx:
            return .vote
        // Kujira and Osmosis offer exactly one operation, `.cosmosIBC`, and
        // it is migrated to `Features/FunctionTransaction/`. That is the
        // same shape as dYdX's `.vote` above: a single-operation chain's
        // entry point passes straight through the action list to the
        // migrated screen without ever consulting this default, so naming
        // the migrated type here is honest rather than a defect —
        // `testASingleActionChainMayDefaultToItsOnlyMigratedOperation` is
        // what pins that exemption.
        case .kujira, .osmosis:
            return .cosmosIBC
        // Gaia offers two operations, `.cosmosIBC` and `.theSwitch`, and both
        // are migrated — unlike Kujira/Osmosis there is no unmigrated
        // operation left to point the legacy dropdown default at. It falls
        // through to `.custom` instead: unreachable in practice, since every
        // row Gaia offers routes through the action list to a migrated
        // screen, but a default that names a migrated type is what
        // `testNoMultiActionChainDefaultsToAMigratedFunction` exists to
        // catch for chains the dropdown can still be entered on.
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP
        default:
            return .custom
        }
    }
}
