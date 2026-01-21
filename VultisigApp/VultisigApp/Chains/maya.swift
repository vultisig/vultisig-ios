//
//  maya.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation
import Tss
import WalletCore
import CryptoSwift

enum MayaChainHelper {
    static let MayaChainGas: UInt64 = 2000000000
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain, hrp: "maya") else {
            throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
        }
        guard case .MayaChain(let accountNumber, let sequence, let isDeposit) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        var mayaChainCoin = TW_Cosmos_Proto_THORChainCoin()
        var message = [WalletCore.CosmosMessage()]
        
        if isDeposit {
            mayaChainCoin = TW_Cosmos_Proto_THORChainCoin.with {
                $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                    $0.chain = "MAYA"
                    $0.symbol = "CACAO"
                    $0.ticker = "CACAO"
                    $0.synth = false
                }
                if keysignPayload.toAmount > 0 {
                    $0.amount = String(keysignPayload.toAmount)
                    $0.decimals = Int64(keysignPayload.coin.decimals)
                }
            }
            message = [WalletCore.CosmosMessage.with {
                $0.thorchainDepositMessage = WalletCore.CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [mayaChainCoin]
                }
            }]
        } else {
            guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .thorchain, hrp: "maya") else {
                throw HelperError.runtimeError("\(keysignPayload.toAddress) is invalid")
            }
            
            message = [WalletCore.CosmosMessage.with {
                $0.thorchainSendMessage = WalletCore.CosmosMessage.THORChainSend.with {
                    $0.fromAddress = fromAddr.data
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = keysignPayload.coin.ticker.lowercased()
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = toAddress.data
                }
            }]
        }
        
        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = "mayachain-mainnet-v1"
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = message
            // MAYAChain fee is 0.02 CACAO
            $0.fee = WalletCore.CosmosFee.with {
                $0.gas = MayaChainGas
            }
        }
        
        return try input.serializedData()
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(coinHexPubKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    static func getSignedTransaction(coinHexPubKey: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPubKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .thorchain,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let transactionHash = CosmosSerializedParser.getTransactionHash(from: serializedData)
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash: transactionHash)
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed maya transaction,error:\(error.localizedDescription)")
        }
    }
}
