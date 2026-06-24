//
//  TronRouteBuilder.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronRouteBuilder {

    @ViewBuilder
    func buildMainScreen(vault: Vault) -> some View {
        TronView(vault: vault)
    }

    @ViewBuilder
    func buildFreezeScreen(vault: Vault) -> some View {
        TronFreezeView(vault: vault)
    }

    @ViewBuilder
    func buildUnfreezeScreen(vault: Vault, frozenBandwidth: Decimal, frozenEnergy: Decimal) -> some View {
        TronUnfreezeView(
            vault: vault,
            frozenBandwidthBalance: frozenBandwidth,
            frozenEnergyBalance: frozenEnergy
        )
    }
}
