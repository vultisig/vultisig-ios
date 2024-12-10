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
        
        // TODO: Create a Ripple one, for testing I am reusing this from Cosmos.
        guard case .Cosmos(_, let sequence, let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData: fail to get account number and sequence")
        }
        
        guard AnyAddress(string: keysignPayload.toAddress, coin: .xrp) != nil else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        let publicKey = try CoinFactory.publicKey(asset: keysignPayload.coin.toCoinMeta(), vault: vault)
        
        let operation = RippleOperationPayment.with {
            
            if let memo = keysignPayload.memo  {
                $0.destinationTag = Int64(memo) ?? 0
            }
            
            $0.destination = keysignPayload.toAddress
            $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
        }
        
        let input = RippleSigningInput.with {
            $0.fee = Int64(gas)
            $0.sequence = Int32(sequence) // from account info api
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
        return [preSigningOutput.dataHash.hexString]
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
        
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        
        let signatureProvider = SignatureProvider(signatures: signatures)
        
        // If I use datahash it is not finding anything
        let signature = signatureProvider.getDerSignature(preHash: preSigningOutput.dataHash)
        guard publicKey.verifyAsDER(signature: signature, message: preSigningOutput.dataHash) else {
            let errorMessage = "Invalid signature"
            print("\(errorMessage)")
                  throw HelperError.runtimeError(errorMessage)
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: publicKey.data)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .xrp,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try RippleSigningOutput(serializedData: compileWithSignature)
        
        // The error is HERE it accepted it as a DER previously
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

