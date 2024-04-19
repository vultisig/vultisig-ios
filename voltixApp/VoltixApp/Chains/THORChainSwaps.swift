//
//  THORChainSwaps.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

class THORChainSwaps {
    let vaultHexPublicKey: String
    let vaultHexChainCode: String
    
    init(vaultHexPublicKey: String, vaultHexChainCode: String) {
        self.vaultHexPublicKey = vaultHexPublicKey
        self.vaultHexChainCode = vaultHexChainCode
    }
    
    static let affiliateFeeAddress = "v0"
    func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let input = THORChainSwapSwapInput.with {
            $0.fromAsset = swapPayload.fromAsset
            $0.fromAddress = swapPayload.fromAddress
            $0.toAsset = swapPayload.toAsset
            $0.toAddress = swapPayload.toAddress
            $0.vaultAddress = swapPayload.vaultAddress
            $0.routerAddress = swapPayload.routerAddress ?? ""
            $0.fromAmount = swapPayload.fromAmount
            $0.toAmountLimit = swapPayload.toAmountLimit
            $0.streamParams = .with {
                $0.interval = swapPayload.streamingInterval
                $0.quantity = swapPayload.streamingQuantity
            }
            $0.affiliateFeeAddress = THORChainSwaps.affiliateFeeAddress
            $0.affiliateFeeRateBp = "70"
        }
        do {
            let inputData = try input.serializedData()
            let outputData = THORChainSwap.buildSwap(input: inputData)
            let output = try THORChainSwapSwapOutput(serializedData: outputData)
            switch swapPayload.fromAsset.chain {
            case .thor:
                return THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload, signingInput: output.cosmos)
            case .btc:
                let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
            case .bch:
                let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
            case .ltc:
                let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
            case .doge:
                let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
            case .eth:
                return EVMHelper.getEthereumHelper().getPreSignedInputData(signingInput: output.ethereum, keysignPayload: keysignPayload)
            case .bsc:
                return EVMHelper.getBSCHelper().getPreSignedInputData(signingInput: output.ethereum, keysignPayload: keysignPayload)
            case .avax:
                return EVMHelper.getAvaxHelper().getPreSignedInputData(signingInput: output.ethereum, keysignPayload: keysignPayload)
            case .atom:
                return ATOMHelper().getSwapPreSignedInputData(keysignPayload:keysignPayload, signingInput: output.cosmos)
            default:
                return .failure(HelperError.runtimeError("not support yet"))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        guard let swapPayload = keysignPayload.swapPayload else {
            return .failure(HelperError.runtimeError("no swap payload"))
        }
        let result = self.getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload)
        do {
            switch result {
            case .success(let inputData):
                switch swapPayload.fromAsset.chain {
                case .thor:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                case .btc:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
                    let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
                    return .success(preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString })
                case .ltc:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .litecoin, txInputData: inputData)
                    let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
                    return .success(preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString })
                case .bch:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .bitcoinCash, txInputData: inputData)
                    let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
                    return .success(preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString })
                case .doge:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .dogecoin, txInputData: inputData)
                    let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
                    return .success(preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString })
                case .eth:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                case .bsc:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .smartChain, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                case .avax:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .avalancheCChain, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                case .atom:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .cosmos, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                default:
                    return .failure(HelperError.runtimeError("not support yet"))
                }
            case .failure(let err):
                return .failure(err)
            }
            
        } catch {
            return .failure(error)
        }
    }
    
    func getSignedTransaction(keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        guard let swapPayload = keysignPayload.swapPayload else {
            return .failure(HelperError.runtimeError("no swap payload"))
        }
        
        let result = self.getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            switch swapPayload.fromAsset.chain {
            case .thor:
                return THORChainHelper.getSignedTransaction(vaultHexPubKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode, inputData: inputData, signatures: signatures)
            case .btc:
                let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
            case .bch:
                let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
            case .ltc:
                let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
            case .doge:
                let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode)
                return utxoHelper.getSignedTransaction(inputData: inputData, signatures: signatures)
            case .eth:
                return EVMHelper.getEthereumHelper().getSignedTransaction(vaultHexPubKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode, inputData: inputData, signatures: signatures)
            case .bsc:
                return EVMHelper.getBSCHelper().getSignedTransaction(vaultHexPubKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode, inputData: inputData, signatures: signatures)
            case .avax:
                return EVMHelper.getAvaxHelper().getSignedTransaction(vaultHexPubKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode, inputData: inputData, signatures: signatures)
            case .atom:
                return ATOMHelper().getSignedTransaction(vaultHexPubKey: self.vaultHexPublicKey, vaultHexChainCode: self.vaultHexChainCode, inputData: inputData, signatures: signatures)
            default:
                return .failure(HelperError.runtimeError("not support"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
