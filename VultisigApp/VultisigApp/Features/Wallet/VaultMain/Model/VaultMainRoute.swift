//
//  VaultMainRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

enum VaultMainRoute: Equatable, Hashable {
    case settings
    case createVault
    case mainAction(VaultAction)
}

enum VaultAction: Equatable, Hashable {
    case send(coin: Coin?, hasPreselectedCoin: Bool)
    case swap(fromCoin: Coin)
    case function(coin: Coin?)
    case buy(address: String, blockChainCode: String, coinType: String)
    case signMessage(method: String, message: String, chain: String, autoSign: Bool, callbackUrl: String?)
}
