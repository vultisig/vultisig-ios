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

    // MARK: - ERC20 Approval Methods
    
    func getPreSignedApproveInputData(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> Data {
        let approveInput = EthereumSigningInput.with {
            $0.transaction = .with {
                $0.erc20Approve = .with {
                    $0.amount = approvePayload.amount.magnitude.serialize()
                    $0.spender = approvePayload.spender
                }
            }
            $0.toAddress = keysignPayload.coin.contractAddress
        }
        
        let inputData = try EVMHelper.getHelper(coin: keysignPayload.coin).getPreSignedInputData(
            signingInput: approveInput, 
            keysignPayload: keysignPayload
        )
        return inputData
    }

    func getPreSignedApproveImageHash(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: keysignPayload.coin.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    func getSignedApproveTransaction(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin).getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedEvmTx
    }
}

private extension KyberSwaps {

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

        let baseGas = Int64(quote.data.gas) ?? 600000
        let gasMultiplierTimes10: Int64
        
        switch keysignPayload.coin.chain {
        case .ethereum:
            gasMultiplierTimes10 = 14
        case .arbitrum, .optimism, .base, .polygon, .avalanche, .bscChain:
            gasMultiplierTimes10 = 20
        default:
            gasMultiplierTimes10 = 16
        }
        
        let bufferedGas = (baseGas * gasMultiplierTimes10) / 10
        let gas = BigUInt(bufferedGas)
        
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
        
        let chainIdString = keysignPayload.coin.chain == .ethereumSepolia ? "11155111" : keysignPayload.coin.coinType.chainId
        guard let intChainID = Int(chainIdString) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        
        let incrementNonceValue: Int64 = incrementNonce ? 1 : 0
        
        var modifiedInput = input
        modifiedInput.chainID = Data(hexString: Int64(intChainID).hexString())!
        modifiedInput.nonce = Data(hexString: (nonce + incrementNonceValue).hexString())!
        modifiedInput.gasLimit = customGasLimit.serialize()
        modifiedInput.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
        modifiedInput.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
        modifiedInput.txMode = .enveloped
        
        return try modifiedInput.serializedData()
    }
} 