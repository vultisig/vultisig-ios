//
//  Sui.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 23/04/24.
//

import Foundation
import Tss
import BigInt

enum SuiHelper {
    
    static let defaultFeeInSui: BigInt = 1000  // Example fee, adjust as necessary
    
    static func getSui(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            TokensStore.createNewCoinInstance(ticker: "SUI", address: addr, hexPublicKey: hexPubKey, coinType: .sui)
        }
    }
    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        // Sui is using EdDSA , so it doesn't need to use HD derive
        guard let pubKeyData = Data(hexString: hexPubKey) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        guard let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        return .success(CoinType.sui.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "SUI" else {
            return .failure(HelperError.runtimeError("coin is not SUI"))
        }
        
        guard case .Sui(let referenceGasPrice, let coins) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("getPreSignedInputData fail to get SUI transaction information from RPC"))
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        let suiCoins = coins.map{
            var obj = SuiObjectRef()
            obj.objectID = $0["objectID"] ?? .empty
            obj.version = UInt64($0["version"] ?? .zero) ?? UInt64.zero
            obj.objectDigest = $0["objectDigest"] ?? .empty
            return obj
        }
        
        let input = SuiSigningInput.with {
            $0.paySui = SuiPaySui.with {
                $0.inputCoins = suiCoins
                $0.recipients = [toAddress.description]
                $0.amounts = [UInt64(keysignPayload.toAmount)]
            }
            // 0.003 SUI
            $0.signer = keysignPayload.coin.address
            $0.gasBudget = 3000000
            $0.referenceGasPrice = UInt64(referenceGasPrice)
        }
        
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get PreSign input data: \(error.localizedDescription)"))
        }
    }
    
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([Hash.blake2b(data: preSigningOutput.data, size: 32).hexString])
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
                                     signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }
        
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                let preSigningOutputDataBlake2b = Hash.blake2b(data: preSigningOutput.data, size: 32)
                let allSignatures = DataVector()
                let publicKeys = DataVector()
                let signatureProvider = SignatureProvider(signatures: signatures)
                let signature = signatureProvider.getSignature(preHash: preSigningOutputDataBlake2b)
                guard publicKey.verify(signature: signature, message: preSigningOutputDataBlake2b) else {
                    print("SUI signature verification failed")
                    return .failure(HelperError.runtimeError("SUI signature verification failed"))
                }
                
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .sui,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                let output = try SuiSigningOutput(serializedData: compileWithSignature)
                let result = SignedTransactionResult(rawTransaction: output.unsignedTx, transactionHash: .empty, signature: output.signature)
                return .success(result)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed SUI transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
