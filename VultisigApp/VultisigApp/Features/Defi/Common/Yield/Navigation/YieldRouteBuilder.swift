//
//  YieldRouteBuilder.swift
//  VultisigApp
//

import SwiftUI

struct YieldRouteBuilder {

    @ViewBuilder
    func buildMainScreen(vault: Vault, providerID: DefiYieldProviderID) -> some View {
        YieldVaultScreen(vault: vault, providerID: providerID)
    }

    @ViewBuilder
    func buildDepositScreen(vault: Vault, providerID: DefiYieldProviderID) -> some View {
        YieldDepositScreen(vault: vault, providerID: providerID)
    }

    @MainActor
    @ViewBuilder
    func buildWithdrawScreen(vault: Vault, providerID: DefiYieldProviderID, model: YieldViewModel) -> some View {
        YieldWithdrawScreen(vault: vault, providerID: providerID, model: model)
    }
}
