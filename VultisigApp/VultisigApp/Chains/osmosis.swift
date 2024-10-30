//
//  Osmosis.swift
//  VultisigApp
//
//  Created by Enrique Souza 29/10/2024
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class OsmoHelper {
    let coinType: CoinType
    
    init(){
        self.coinType = CoinType.osmosis
    }
    
    static let OsmoGasLimit:UInt64 = 200000
    
    func getSwapPreSignedInputData(keysignPayload: KeysignPayload, signingInput: CosmosSigningInput) throws -> Data {
        
        guard case .Cosmos(let accountNumber, let sequence,let gas, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        var input = signingInput
        input.publicKey = pubKeyData
        input.accountNumber = accountNumber
        input.sequence = sequence
        input.mode = .sync
        
        input.fee = CosmosFee.with {
            $0.gas = OsmoHelper.OsmoGasLimit
            $0.amounts = [CosmosAmount.with {
                $0.denom = "uosmo"
                $0.amount = String(gas)
            }]
        }
        return try input.serializedData()
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard case .Cosmos(let accountNumber, let sequence , let gas, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = self.coinType.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = [CosmosMessage.with {
                $0.sendCoinsMessage = CosmosMessage.Send.with{
                    $0.fromAddress = keysignPayload.coin.address
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "uosmo"
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = keysignPayload.toAddress
                }
            }]
            
            $0.fee = CosmosFee.with {
                $0.gas = OsmoHelper.OsmoGasLimit
                $0.amounts = [CosmosAmount.with {
                    $0.denom = "uosmo"
                    $0.amount = String(gas)
                }]
            }
        }
        
        return try input.serializedData()
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let cosmosPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: cosmosPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(cosmosPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)")
        }
    }
}
