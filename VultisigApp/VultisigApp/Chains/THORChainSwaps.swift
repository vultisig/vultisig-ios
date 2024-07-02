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

    static let affiliateFeeAddress = "vi"

    let vaultHexPublicKey: String
    let vaultHexChainCode: String
    
    init(vaultHexPublicKey: String, vaultHexChainCode: String) {
        self.vaultHexPublicKey = vaultHexPublicKey
        self.vaultHexChainCode = vaultHexChainCode
    }
    
    func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        let input = THORChainSwapSwapInput.with {
            $0.fromAsset = swapPayload.fromAsset
            $0.fromAddress = swapPayload.fromAddress
            $0.toAsset = swapPayload.toAsset
            $0.toAddress = swapPayload.toAddress
            $0.vaultAddress = swapPayload.vaultAddress
            $0.routerAddress = swapPayload.routerAddress ?? ""
            $0.fromAmount = String(swapPayload.fromAmount)
            $0.toAmountLimit = swapPayload.toAmountLimit
            $0.expirationTime = swapPayload.expirationTime
            $0.streamParams = .with {
                $0.interval = swapPayload.streamingInterval
                $0.quantity = swapPayload.streamingQuantity
            }
            if swapPayload.isAffiliate {
                $0.affiliateFeeAddress = THORChainSwaps.affiliateFeeAddress
                $0.affiliateFeeRateBp = THORChainSwaps.affiliateFeeRateBp
            }
        }

        let inputData = try input.serializedData()
        let outputData = THORChainSwap.buildSwap(input: inputData)

        let output = try THORChainSwapSwapOutput(serializedData: outputData)
        switch swapPayload.fromAsset.chain {
        case .thor:
            return try THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload, signingInput: output.cosmos)
        case .btc, .bch, .ltc, .doge:
            let helper = UTXOChainsHelper(coin: swapPayload.fromCoin.coinType, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
            return try helper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
        case .eth, .bsc, .avax:
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin.toCoinMeta())
            let signedEvmTx = try helper.getPreSignedInputData(signingInput: output.ethereum, keysignPayload: keysignPayload, incrementNonce: incrementNonce)
            return signedEvmTx
        case .atom:
            return try ATOMHelper().getSwapPreSignedInputData(keysignPayload:keysignPayload, signingInput: output.cosmos)
        default:
            throw HelperError.runtimeError("not support yet")
        }
    }
    
    func getPreSignedImageHash(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let inputData = try getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload, incrementNonce: incrementNonce)

        switch swapPayload.fromAsset.chain {
        case .thor:
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
        case .btc:
            let hashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .ltc:
            let hashes = TransactionCompiler.preImageHashes(coinType: .litecoin, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .bch:
            let hashes = TransactionCompiler.preImageHashes(coinType: .bitcoinCash, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .doge:
            let hashes = TransactionCompiler.preImageHashes(coinType: .dogecoin, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .eth:
            let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
        case .bsc:
            let hashes = TransactionCompiler.preImageHashes(coinType: .smartChain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
        case .avax:
            let hashes = TransactionCompiler.preImageHashes(coinType: .avalancheCChain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
        case .atom:
            let hashes = TransactionCompiler.preImageHashes(coinType: .cosmos, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            return [preSigningOutput.dataHash.hexString]
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
        let inputData = try EVMHelper.getHelper(coin: keysignPayload.coin.toCoinMeta()).getPreSignedInputData(
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
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        return [preSigningOutput.dataHash.hexString]
    }

    func getSignedApproveTransaction(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin.toCoinMeta()).getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedEvmTx
    }

    func getSignedTransaction(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {

        let inputData = try getPreSignedInputData(
            swapPayload: swapPayload,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
            
        switch swapPayload.fromAsset.chain {
        case .thor:
            return try THORChainHelper.getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        case .btc:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .bch:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .ltc:
            let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .doge:
            let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode)
            return try utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
        case .eth, .bsc, .avax:
            let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin.toCoinMeta()).getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            return signedEvmTx
        case .atom:
            return try ATOMHelper().getSignedTransaction(vaultHexPubKey: vaultHexPublicKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        default:
            throw HelperError.runtimeError("not support")
        }
    }
}
