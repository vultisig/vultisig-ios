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

enum TronHelper {
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TRX" else {
            throw HelperError.runtimeError("coin is not TRX")
        }
        
        guard case .Tron(let timestamp, let expiration, let blockHeaderTimestamp, let blockHeaderNumber, let blockHeaderVersion, let blockHeaderTxTrieRoot, let blockHeaderParentHash, let blockHeaderWitnessAddress) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
                
        let contract = TronTransferContract.with {
            $0.ownerAddress = keysignPayload.coin.address
            $0.toAddress = keysignPayload.toAddress
            $0.amount = Int64(keysignPayload.toAmount)
        }

        let input = TronSigningInput.with {
            $0.transaction = TronTransaction.with {
                $0.contractOneof = .transfer(contract)
                $0.timestamp = Int64(timestamp)
                $0.blockHeader = TronBlockHeader.with {
                    $0.timestamp = Int64(blockHeaderTimestamp)
                    $0.number = Int64(blockHeaderNumber)
                    $0.version = Int32(blockHeaderVersion)
                    $0.txTrieRoot = Data(
                        hexString: blockHeaderTxTrieRoot
                    )!
                    $0.parentHash = Data(
                        hexString: blockHeaderParentHash
                    )!
                    $0.witnessAddress = Data(
                        hexString: blockHeaderWitnessAddress
                    )!
                }
                $0.expiration = Int64(expiration)
            }
        }
        
        return try input.serializedData()
        
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .ton,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }
    
    static func getSignedTransaction(
vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError
                .runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError
                .runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .ton,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(
            preHash: preSigningOutput.data
        )
        guard publicKey
            .verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ton,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try TheOpenNetworkSigningOutput(
            serializedBytes: compileWithSignature
        )
        
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: output.hash.hexString)
        
        return result
    }
}

