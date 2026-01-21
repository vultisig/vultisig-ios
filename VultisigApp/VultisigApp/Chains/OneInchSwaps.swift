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

    func getPreSignedImageHash(payload: GenericSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let inputData = try getPreSignedInputData(
            quote: payload.quote,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: payload.fromCoin.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    func getSignedTransaction(payload: GenericSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(
            quote: payload.quote,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let transaction = try helper.getSignedTransaction(ethPublicKey: keysignPayload.coin.hexPublicKey,
            inputData: inputData,
            signatures: signatures
        )
        return transaction
    }
}

private extension OneInchSwaps {

    func getPreSignedInputData(quote: EVMQuote, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                }
            }
        }

        // Get gasPrice from quote, but ensure it's not too low
        var gasPrice = BigUInt(quote.tx.gasPrice) ?? BigUInt.zero

        // sometimes the `gas` field in oneinch tx is 0
        // when it is 0, we need to override it with defaultETHSwapGasUnit(600000)
        var normalizedGas = quote.tx.gas == 0 ? EVMHelper.defaultETHSwapGasUnit : quote.tx.gas

        // For swap providers like LiFi, their gasPrice might be outdated or too low
        // Compare with the calculated network fees and use the higher value
        if case .Ethereum(let maxFeePerGasWei, _, _, let gasLimit) = keysignPayload.chainSpecific {
            let calculatedGasPrice = BigUInt(maxFeePerGasWei)
            // Use the maximum of provider's gasPrice and our calculated maxFeePerGas
            // This ensures transactions won't get stuck due to low gas prices
            gasPrice = max(gasPrice, calculatedGasPrice)

            // For all EVM chains, ensure we use at least the gas limit from keysignPayload
            // This prevents insufficient gas errors when swap providers return lower values
            normalizedGas = max(normalizedGas, Int64(gasLimit))
        }

        let gas = BigUInt(normalizedGas)
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = try helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice, incrementNonce: incrementNonce)
        return signed
    }
}
