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
        
        guard case .Tron(let timestamp, let expiration, let blockHeaderTimestamp, let blockHeaderNumber, let blockHeaderVersion, let blockHeaderTxTrieRoot, let blockHeaderParentHash, let blockHeaderWitnessAddress, let gasEstimation) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        guard AnyAddress(string: keysignPayload.toAddress, coin: .tron) != nil else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard Data(hexString: keysignPayload.coin.hexPublicKey) != nil else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        if keysignPayload.coin.isNativeToken {
            
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
            
        } else {
            
            let contract = TronTransferTRC20Contract.with {
                $0.toAddress = keysignPayload.toAddress
                $0.contractAddress = keysignPayload.coin.contractAddress
                $0.ownerAddress = keysignPayload.coin.address
                $0.amount = keysignPayload.toAmount.serialize()
            }
            
            let input = TronSigningInput.with {
                $0.transaction = TronTransaction.with {
                    $0.feeLimit = 50_000_000 // 50 TRX
                    $0.transferTrc20Contract = contract
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
        
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .tron,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(
        vaultHexPubKey: String,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse],
        vault: Vault
    ) throws -> SignedTransactionResult
    {
        let publicKey = try CoinFactory.publicKey(asset: keysignPayload.coin.toCoinMeta(), vault: vault)
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .tron,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignatureWithRecoveryID(
            preHash: preSigningOutput.dataHash
        )
        guard publicKey
            .verify(signature: signature, message: preSigningOutput.dataHash) else {
            print("fail to verify signature")
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: publicKey.data)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .tron,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try TronSigningOutput(
            serializedBytes: compileWithSignature
        )
        
        if !output.errorMessage.isEmpty {
            print(output.errorMessage)
            throw HelperError.runtimeError("fail to sign transaction")
        }
        
        let result = SignedTransactionResult(rawTransaction: output.json,
                                             transactionHash: output.id.hexString)
        
        return result
    }
}

