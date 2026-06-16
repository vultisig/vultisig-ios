//
//  YieldRouteBuilder.swift
//  VultisigApp
//

import SwiftUI

struct YieldRouteBuilder {

    @ViewBuilder
    func buildMainScreen(vault: Vault, providerID: DefiYieldProviderID) -> some View {
        YieldVaultView(vault: vault, providerID: providerID)
    }

    @ViewBuilder
    func buildDepositScreen(vault: Vault, providerID: DefiYieldProviderID) -> some View {
        YieldDepositView(vault: vault, providerID: providerID)
    }

    @MainActor
    @ViewBuilder
    func buildWithdrawScreen(vault: Vault, providerID: DefiYieldProviderID, model: YieldViewModel) -> some View {
        YieldWithdrawView(vault: vault, providerID: providerID, model: model)
    }
}
