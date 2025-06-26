//
//  KyberSwaps.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import WalletCore
import BigInt
import Tss

struct KyberSwaps {

    let vaultHexPublicKey: String
    let vaultHexChainCode: String

    func getPreSignedImageHash(payload: KyberSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
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

    func getSignedTransaction(payload: KyberSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {
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

    func getPreSignedInputData(quote: KyberSwapQuote, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                }
            }
        }

        let gas = BigUInt(quote.gasForChain(keysignPayload.coin.chain))
        
        let signed = try getPreSignedInputDataWithCustomGasLimit(
            input: input,
            keysignPayload: keysignPayload,
            customGasLimit: gas,
            incrementNonce: incrementNonce
        )
        
        return signed
    }
    
    func getPreSignedInputDataWithCustomGasLimit(
        input: EthereumSigningInput,
        keysignPayload: KeysignPayload,
        customGasLimit: BigUInt,
        incrementNonce: Bool
    ) throws -> Data {
        guard case .Ethereum(
            let maxFeePerGasWei,
            let priorityFeeWei,
            let nonce,
            _
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }
        
        // Apply 1 GWEI minimum for KyberSwap transactions
        let oneGweiInWei = BigInt(1_000_000_000) // 1 GWEI = 10^9 Wei
        let correctedPriorityFee = max(priorityFeeWei, oneGweiInWei)
        let correctedMaxFeePerGas = max(maxFeePerGasWei, correctedPriorityFee, oneGweiInWei)
        
        let chainIdString = keysignPayload.coin.chain == .ethereumSepolia ? "11155111" : keysignPayload.coin.coinType.chainId
        guard let intChainID = Int(chainIdString) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        
        let incrementNonceValue: Int64 = incrementNonce ? 1 : 0
        
        var modifiedInput = input
        modifiedInput.chainID = Data(hexString: Int64(intChainID).hexString())!
        modifiedInput.nonce = Data(hexString: (nonce + incrementNonceValue).hexString())!
        modifiedInput.gasLimit = customGasLimit.serialize()
        modifiedInput.maxFeePerGas = correctedMaxFeePerGas.magnitude.serialize()
        modifiedInput.maxInclusionFeePerGas = correctedPriorityFee.magnitude.serialize()
        modifiedInput.txMode = .enveloped
        
        return try modifiedInput.serializedData()
    }
} 
