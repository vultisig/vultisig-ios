//
//  Ton.Swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum TonHelper {
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TON" else {
            throw HelperError.runtimeError("coin is not TON")
        }
        
        guard case .Ton(let sequenceNumber, let expireAt, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let transfer = TheOpenNetworkTransfer.with {
            $0.dest = toAddress.description
            $0.amount = UInt64(keysignPayload.toAmount.description) ?? 0
            $0.mode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)
            
            if let memo = keysignPayload.memo  {
                $0.comment = memo
                // If it is a deposit or a withdraw for staking function, then it can be bounceable
                $0.bounceable = (memo.trimmingCharacters(in: .whitespacesAndNewlines) == "d" ||
                                 memo.trimmingCharacters(in: .whitespacesAndNewlines) == "w")
                
            }
            
        }
        
        let input = TheOpenNetworkSigningInput.with {
            $0.messages = [transfer]
            $0.sequenceNumber = UInt32(sequenceNumber.description) ?? 0
            $0.expireAt = UInt32(expireAt.description) ?? 0
            $0.walletVersion = TheOpenNetworkWalletVersion.walletV4R2
            $0.publicKey = pubKeyData
        }
        
        return try input.serializedData()
        
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ton,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try TheOpenNetworkSigningOutput(serializedData: compileWithSignature)
        
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: output.hash.base64EncodedString())
        
        return result
    }
}

