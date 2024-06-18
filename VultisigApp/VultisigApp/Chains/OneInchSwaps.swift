//
//  OneInchSwaps.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.05.2024.
//

import Foundation
import WalletCore
import BigInt
import Tss

struct OneInchSwaps {

    let vaultHexPublicKey: String
    let vaultHexChainCode: String

    func getPreSignedImageHash(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let result = getPreSignedInputData(quote: payload.quote, keysignPayload: keysignPayload, incrementNonce: incrementNonce)

        switch result {
        case .success(let inputData):
            let hashes = TransactionCompiler.preImageHashes(coinType: payload.fromCoin.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
        case .failure(let error):
            throw error
        }
    }

    func getSignedTransaction(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {

        let result = getPreSignedInputData(quote: payload.quote, keysignPayload: keysignPayload, incrementNonce: incrementNonce)

        switch result {
        case .success(let inputData):
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let transaction = try helper.getSignedTransaction(
                vaultHexPubKey: vaultHexPublicKey,
                vaultHexChainCode: vaultHexChainCode,
                inputData: inputData,
                signatures: signatures
            )
            return transaction
        case .failure(let error):
            throw error
        }
    }
}

private extension OneInchSwaps {

    func getPreSignedInputData(quote: OneInchQuote, keysignPayload: KeysignPayload, incrementNonce: Bool) -> Result<Data, Error> {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                }
            }
        }

        let gasPrice = BigUInt(quote.tx.gasPrice) ?? BigUInt.zero
        let gas = BigUInt(EVMHelper.defaultETHSwapGasUnit)
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice, incrementNonce: incrementNonce)
        return signed
    }
}
