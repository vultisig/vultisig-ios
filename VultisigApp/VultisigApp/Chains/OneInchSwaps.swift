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
    
    func getSignedTransaction(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {
        
        let inputData = try getPreSignedInputData(
            quote: payload.quote,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
        
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let transaction = try helper.getSignedTransaction(
            vaultHexPubKey: vaultHexPublicKey,
            vaultHexChainCode: vaultHexChainCode,
            inputData: inputData,
            signatures: signatures
        )
        
        return transaction
    }
}

private extension OneInchSwaps {
    
    func getPreSignedInputData(quote: OneInchQuote, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                }
            }
        }
        
        var gasPrice = BigUInt(quote.tx.gasPrice) ?? BigUInt.zero
        if gasPrice == 0 {
            guard case .Ethereum(let maxFeePerGasWei, _, _, _) = keysignPayload.chainSpecific else {
                throw HelperError.runtimeError("Failed to get valid gas price for transaction")
            }
            gasPrice = maxFeePerGasWei.magnitude
        }
        
        if keysignPayload.coin.chain == .base {
            gasPrice = gasPrice + (gasPrice / 2) * 5 / 3 // Same as multiplier 2.5 from normalizeEVMFee
        }
        
        let normalizedGas = quote.tx.gas == 0 ? EVMHelper.defaultETHSwapGasUnit : quote.tx.gas
        let gas = BigUInt(normalizedGas)
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = try helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice, incrementNonce: incrementNonce)
        return signed
    }
}
