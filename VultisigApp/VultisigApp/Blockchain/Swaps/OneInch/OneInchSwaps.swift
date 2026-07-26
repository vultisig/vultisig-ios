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

        // Reconcile the quote's gas parameters with the fee oracle through the
        // shared calculator. `EVMSwapFee` is the single source of truth for
        // this formula: the verify/details screens, the co-signer, and the
        // gas-sufficiency validation all price the swap through it, so what
        // is displayed and validated is exactly what gets signed here.
        let oracleMaxFeePerGasWei: BigInt
        let oracleGasLimit: BigInt
        if case .Ethereum(let maxFeePerGasWei, _, _, let gasLimit) = keysignPayload.chainSpecific {
            oracleMaxFeePerGasWei = maxFeePerGasWei
            oracleGasLimit = gasLimit
        } else {
            oracleMaxFeePerGasWei = .zero
            oracleGasLimit = .zero
        }
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: EVMSwapFee.quoteGasPriceWei(quote.tx.gasPrice),
            quoteGas: BigInt(quote.tx.gas),
            maxFeePerGasWei: oracleMaxFeePerGasWei,
            gasLimit: oracleGasLimit
        )

        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = try helper.getPreSignedInputData(
            signingInput: input,
            keysignPayload: keysignPayload,
            gas: effective.gasLimit.magnitude,
            gasPrice: effective.gasPriceWei.magnitude,
            incrementNonce: incrementNonce
        )
        return signed
    }
}
