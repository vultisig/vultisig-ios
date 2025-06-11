//
//  KyberSwaps.swift
//  VultisigApp
//
//  Created by AI Assistant on [Current Date].
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

        let gasPrice = BigUInt(quote.tx.gasPrice) ?? BigUInt("20000000000") // Use gasPrice from quote or 20 Gwei default
        
        // Apply chain-specific gas buffer based on chain costs and execution characteristics
        let baseGas = Int64(quote.data.gas) ?? 600000 // Use raw API gas, not pre-buffered quote.tx.gas
        let gasMultiplier: Double
        
        switch keysignPayload.coin.chain {
        case .ethereum:
            gasMultiplier = 1.4 // 40% buffer - conservative for expensive Ethereum gas
        case .arbitrum, .optimism, .base, .polygon, .avalanche, .bscChain:
            gasMultiplier = 2.0 // 100% buffer - L2s have cheap gas and complex routing
        default:
            gasMultiplier = 1.6 // 60% buffer - reasonable default for other chains
        }
        
        let bufferedGas = Int64(Double(baseGas) * gasMultiplier)
        let gas = BigUInt(bufferedGas)
        
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = try helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice, incrementNonce: incrementNonce)
        return signed
    }
} 