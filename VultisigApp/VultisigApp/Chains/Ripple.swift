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

enum RippleHelper {
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload, vault: Vault) throws -> Data {
        
        guard keysignPayload.coin.chain == Chain.ripple else {
            throw HelperError.runtimeError("coin is not XRP")
        }
        
        guard case .Cosmos(let accountNumber, let sequence , _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData: fail to get account number and sequence")
        }
        
        guard AnyAddress(string: keysignPayload.toAddress, coin: .xrp) != nil else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        let publicKey = try CoinFactory.publicKey(asset: keysignPayload.coin.toCoinMeta(), vault: vault)
        
        let operation = RippleOperationPayment.with {
            $0.destination = keysignPayload.toAddress
            $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
        }
        
        let input = RippleSigningInput.with {
            $0.fee = 10
            $0.sequence = Int32(sequence) // from account info api
            $0.lastLedgerSequence = Int32(accountNumber)
            $0.account = keysignPayload.coin.address
            $0.publicKey = publicKey.data
            $0.opPayment = operation
        }
        
        return try input.serializedData()
        
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload, vault: Vault) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload, vault: vault)
        let hashes = TransactionCompiler.preImageHashes(coinType: .xrp, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse],
                                     vault: Vault
    ) throws -> SignedTransactionResult
    {
        
        
        let publicKey = try CoinFactory.publicKey(asset: keysignPayload.coin.toCoinMeta(), vault: vault)
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload, vault: vault)
        
        let hashes = TransactionCompiler.preImageHashes(coinType: .xrp, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        
        
        let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
        guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: publicKey.data)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .xrp,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try RippleSigningOutput(serializedData: compileWithSignature)
        
        if !output.errorMessage.isEmpty {
            let errorMessage = output.errorMessage
            print("errorMessage: \(errorMessage)")
            throw HelperError.runtimeError(errorMessage)
        }
        
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: output.encoded.base64EncodedString())
        
        return result
    }
}

