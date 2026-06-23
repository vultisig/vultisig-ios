//
//  DefiYieldProviderFactory.swift
//  VultisigApp
//

import Foundation

/// Resolves a `DefiYieldProvider` from its id. Single construction point so the
/// shells, routes, and DeFi-tab rows all share one provider instance shape.
enum DefiYieldProviderFactory {
    static func make(_ id: DefiYieldProviderID) -> DefiYieldProvider {
        switch id {
        case .circle:
            return CircleYieldProvider()
        case .vult:
            return VultYieldProvider()
        }
    }
}
