//
//  SendCryptoDoneContent.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

struct SendCryptoContent {
    let coin: Coin
    let amountCrypto: String
    let amountFiat: String
    let hash: String
    let explorerLink: String
    let memo: String
    let isSend: Bool
    
    let fromAddress: String
    let toAddress: String
    let fee: (crypto: String, fiat: String)
}
