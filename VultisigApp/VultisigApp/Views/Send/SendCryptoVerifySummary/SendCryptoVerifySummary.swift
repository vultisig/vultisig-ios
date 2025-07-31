//
//  SendCryptoVerifySummary.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

struct SendCryptoVerifySummary {
    let fromName: String
    let fromAddress: String
    let toAddress: String
    let network: String
    let networkImage: String
    let memo: String
    let memoFunctionDictionary: [String: String]?
    let feeCrypto: String
    let feeFiat: String
    let coinImage: String
    let amount: String
    let coinTicker: String
    
    init(
        fromName: String,
        fromAddress: String,
        toAddress: String,
        network: String,
        networkImage: String,
        memo: String,
        // Only for Function Calls
        memoFunctionDictionary: [String : String]? = nil,
        feeCrypto: String,
        feeFiat: String,
        coinImage: String,
        amount: String,
        coinTicker: String
    ) {
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.network = network
        self.networkImage = networkImage
        self.memo = memo
        self.memoFunctionDictionary = memoFunctionDictionary
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.coinImage = coinImage
        self.amount = amount
        self.coinTicker = coinTicker
    }
}
