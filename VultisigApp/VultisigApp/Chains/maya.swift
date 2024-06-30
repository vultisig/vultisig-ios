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
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload, signingInput: CosmosSigningInput) -> Result<Data, Error> {
        guard case .MayaChain(let accountNumber, let sequence) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        var input = signingInput
        input.publicKey = pubKeyData
        input.accountNumber = accountNumber
        input.sequence = sequence
        input.mode = .sync
        // THORChain fee is 0.02 RUNE
        input.fee = CosmosFee.with {
            $0.gas = MayaChainGas
        }
        // memo has been set
        // deposit message has been set
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain, hrp: "maya") else {
            return .failure(HelperError.runtimeError("\(keysignPayload.coin.address) is invalid"))
        }
        
        guard case .MayaChain(let accountNumber, let sequence) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        
        var mayaChainCoin = TW_Cosmos_Proto_THORChainCoin()
        var message = [CosmosMessage()]
        
        var isDeposit: Bool = false
        if let memo = keysignPayload.memo, !memo.isEmpty {
            if DepositStore.PREFIXES.contains(where: { memo.hasPrefix($0) }) {
                isDeposit = true
            }
        }
        
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
            message = [CosmosMessage.with {
                $0.thorchainDepositMessage = CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [mayaChainCoin]
                }
            }]
        } else {
            guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .thorchain, hrp: "maya") else {
                return .failure(HelperError.runtimeError("\(keysignPayload.toAddress) is invalid"))
            }
            
            message = [CosmosMessage.with {
                $0.thorchainSendMessage = CosmosMessage.THORChainSend.with {
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
            $0.fee = CosmosFee.with {
                $0.gas = MayaChainGas
            }
        }
        print(input.debugDescription)
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            
        case .failure(let error):
            throw error
        }
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let thorPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: CoinType.thorchain.derivationPath())
        guard let pubkeyData = Data(hexString: thorPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(thorPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
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
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .thorchain,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)")
        }
    }
}
