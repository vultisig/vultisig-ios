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
    let decodedFunctionSignature: String?
    let decodedFunctionArguments: String?
    let memoFunctionDictionary: [String: String]?
    let feeCrypto: String
    let feeFiat: String
    let isCalculatingFee: Bool
    let coinImage: String
    let amount: String
    let coinTicker: String
    let keysignPayload: KeysignPayload?

    init(
        fromName: String,
        fromAddress: String,
        toAddress: String,
        network: String,
        networkImage: String,
        memo: String,
        // Only for Function Calls
        decodedFunctionSignature: String? = nil,
        decodedFunctionArguments: String? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        feeCrypto: String,
        feeFiat: String,
        isCalculatingFee: Bool = false,
        coinImage: String,
        amount: String,
        coinTicker: String,
        keysignPayload: KeysignPayload? = nil
    ) {
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.network = network
        self.networkImage = networkImage
        self.memo = memo
        self.decodedFunctionSignature = decodedFunctionSignature
        self.decodedFunctionArguments = decodedFunctionArguments
        self.memoFunctionDictionary = memoFunctionDictionary
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.isCalculatingFee = isCalculatingFee
        self.coinImage = coinImage
        self.amount = amount
        self.coinTicker = coinTicker
        self.keysignPayload = keysignPayload
    }
}
