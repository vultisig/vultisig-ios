//
//  THORChainSwaps.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

class THORChainSwaps {
    static var affiliateFeeRateBp: String {
#if DEBUG
        return "0"
#else
        return "50"
#endif
    }
    
    static var referredAffiliateFeeRateBp: String {
        return "35"
    }
    
    static var referredUserFeeRateBp: String {
        return "10"
    }

    static let affiliateFeeAddress = "vi"

    let vaultHexPublicKey: String
    let vaultHexChainCode: String
    let vault: Vault?
    
    init(vaultHexPublicKey: String, vaultHexChainCode: String) {
        self.vaultHexPublicKey = vaultHexPublicKey
        self.vaultHexChainCode = vaultHexChainCode
        self.vault = nil
    }
    
    init (vault: Vault) {
        self.vaultHexPublicKey = vault.hexChainCode
        self.vaultHexChainCode = vault.hexChainCode
        self.vault = vault
    }
    
    func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        switch swapPayload.fromCoin.chain {
        case .thorChain:
            return try THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let helper = UTXOChainsHelper(coin: swapPayload.fromCoin.coinType, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
            let swapInput =  try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
            return try helper.getSigningInputData(keysignPayload: keysignPayload, signingInput: swapInput)
        case .ethereum, .bscChain, .avalanche,.base,.arbitrum:
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let signedEvmTx = try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload, incrementNonce: incrementNonce)
            return signedEvmTx
        case .gaiaChain:
            return try ATOMHelper().getSwapPreSignedInputData(keysignPayload:keysignPayload)
        case .ripple:
            return try RippleHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .tron:
            return try TronHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        default:
            throw HelperError.runtimeError("not support yet")
        }
    }
    
    func getPreSignedImageHash(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let inputData = try getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload, incrementNonce: incrementNonce)

        switch swapPayload.fromCoin.chain {
        case .thorChain,.ethereum, .bscChain,.avalanche,.gaiaChain, .base ,.arbitrum:
            let hashes = TransactionCompiler.preImageHashes(coinType: swapPayload.fromCoin.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            if !preSigningOutput.errorMessage.isEmpty {
                throw HelperError.runtimeError(preSigningOutput.errorMessage)
            }
            return [preSigningOutput.dataHash.hexString]
        case .bitcoin,.litecoin,.bitcoinCash,.dogecoin:
            let hashes = TransactionCompiler.preImageHashes(coinType: swapPayload.fromCoin.coinType, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedBytes: hashes)
            if !preSigningOutput.errorMessage.isEmpty {
                throw HelperError.runtimeError(preSigningOutput.errorMessage)
            }
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .ripple:
            return try RippleHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .tron:
            return try TronHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        default:
            throw HelperError.runtimeError("not support yet")
        }
    }

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

    func getSignedTransaction(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {

        let inputData = try getPreSignedInputData(
            swapPayload: swapPayload,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
            
        switch swapPayload.fromCoin.chain {
        case .thorChain:
            return try THORChainHelper.getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        case .bitcoin:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .bitcoinCash:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .litecoin:
            let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .dogecoin:
            let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .ethereum,.bscChain, .avalanche , .base,.arbitrum:
            let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin).getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            return signedEvmTx
        case .gaiaChain:
            return try ATOMHelper().getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        case .ripple:
            return try RippleHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
        case .tron:
            
            guard let vault = vault else {
                throw HelperError.runtimeError("not support")
            }
            
            return try TronHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures, vault: vault)
        default:
            throw HelperError.runtimeError("not support")
        }
    }
}
