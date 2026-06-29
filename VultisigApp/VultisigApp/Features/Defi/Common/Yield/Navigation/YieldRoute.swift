//
//  YieldRoute.swift
//  VultisigApp
//

enum YieldRoute: Hashable {
    case main(vault: Vault, providerID: DefiYieldProviderID)
    case deposit(vault: Vault, providerID: DefiYieldProviderID)
    case withdraw(vault: Vault, providerID: DefiYieldProviderID, model: YieldViewModel)
}
