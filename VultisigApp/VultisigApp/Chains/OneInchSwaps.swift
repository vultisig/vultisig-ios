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

    func getPreSignedImageHash(payload: OneInchSwapPayload, keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(quote: payload.quote, keysignPayload: keysignPayload)

        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: payload.fromCoin.coinType, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func getSignedTransaction(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error> {

        let result = getPreSignedInputData(quote: payload.quote, keysignPayload: keysignPayload)

        switch result {
        case .success(let inputData):
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let transaction = helper.getSignedTransaction(
                vaultHexPubKey: vaultHexPublicKey,
                vaultHexChainCode: vaultHexChainCode,
                inputData: inputData,
                signatures: signatures
            )
            return transaction
        case .failure(let err):
            return .failure(err)
        }
    }
}

private extension OneInchSwaps {

    func getPreSignedInputData(quote: OneInchQuote, keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = BigUInt(stringLiteral: quote.tx.value).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                }
            }
        }

        let gasPrice = BigUInt(stringLiteral: quote.tx.gasPrice)
        let gas = BigUInt(quote.tx.gas)
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice)
        return signed
    }
}
