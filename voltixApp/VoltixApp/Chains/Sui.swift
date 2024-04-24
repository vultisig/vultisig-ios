//
//  Sui.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 23/04/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum SuiHelper {
    
    static let defaultFeeInSui: BigInt = 1000  // Example fee, adjust as necessary
    
    static func getSui(hexPubKey: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey).flatMap { addr -> Result<Coin, Error> in
            
            guard let address = AnyAddress(string: addr, coin: .sui) else {
                return .failure(HelperError.runtimeError("fail to get to address"))
            }
            
            return TokensStore.createNewCoinInstance(ticker: "SUI", address: address.description, hexPublicKey: hexPubKey, coinType: .sui)
        }
    }
    
    static func deriveSuiAddress(publicKeyBytes: Data) -> String {
        let flagByte = Data([0x00])  // Assuming Ed25519 signature scheme
        let fullBytes = flagByte + publicKeyBytes

        // Using the library's BLAKE2b function with a 256-bit output size
        let hash = Hash.blake2b(data: fullBytes, size: 32)
        return hash.toHexString()
    }

    static func getAddressFromPublicKey(hexPubKey: String) -> Result<String, Error> {
        guard let pubKeyData = Data(hexString: hexPubKey) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        let address = deriveSuiAddress(publicKeyBytes: pubKeyData)
        return .success(address)
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "SUI" else {
            return .failure(HelperError.runtimeError("coin is not SUI"))
        }
        
        guard case .Sui(let referenceGasPrice, let coins) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        let input = SuiSigningInput.with {
            $0.signer = keysignPayload.coin.address
            $0.paySui.recipients = [toAddress.description]
            $0.paySui.amounts = [UInt64(keysignPayload.toAmount)]
            $0.gasBudget = 3000000
            $0.referenceGasPrice = UInt64(referenceGasPrice)
            
            //TODO: we need this object to be passed dynamically
            var obj = TW_Sui_Proto_ObjectRef()
            obj.objectID = "0xb178412541421f7197c920acae730442733945b0bbc6f0140d724984574d5892"
            obj.objectDigest = "HdVG12bPkRc3fPPLtRZmakW6EqN6mhCCFict9ivAGExy"
            obj.version = 96116690
            $0.paySui.inputCoins.append(obj)
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
                print(hashes.hexString)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                print("Sui getPreSignedImageHash hash:\(preSigningOutput.debugDescription)")
                return .success([preSigningOutput.data.hexString])
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
                let allSignatures = DataVector()
                let publicKeys = DataVector()
                let signatureProvider = SignatureProvider(signatures: signatures)
                let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
                guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
                    return .failure(HelperError.runtimeError("fail to verify signature"))
                }
                
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .sui,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                
                
                let output = try SuiSigningOutput(serializedData: compileWithSignature)
                let result = SignedTransactionResult(rawTransaction: output.unsignedTx,
                                                     transactionHash: getHashFromRawTransaction(tx:output.unsignedTx))
                return .success(result)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed SUI transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    static func getHashFromRawTransaction(tx: String) -> String {
        let sig =  Data(tx.prefix(64).utf8)
        return sig.base64EncodedString()
    }
    
}
