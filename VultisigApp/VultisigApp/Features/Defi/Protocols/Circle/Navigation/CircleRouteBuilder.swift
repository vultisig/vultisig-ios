//
//  CircleRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-12-19.
//

import SwiftUI

struct CircleRouteBuilder {

    @ViewBuilder
    func buildMainScreen(vault: Vault) -> some View {
        CircleView(vault: vault)
    }

    @ViewBuilder
    func buildDepositScreen(vault: Vault) -> some View {
        CircleDepositView(vault: vault)
    }

    @ViewBuilder
    func buildWithdrawScreen(vault: Vault, model: CircleViewModel) -> some View {
        CircleWithdrawView(vault: vault, model: model)
    }
}
