//
//  Solana.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum SolanaHelper {
    
    static let defaultFeeInLamports: BigInt = 1000000 //0.001
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SOL" else {
            throw HelperError.runtimeError("coin is not SOL")
        }
        guard case .Solana(let recentBlockHash, let priorityFee, let fromAddressPubKey, let toAddressPubKey) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get to address")
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .solana) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        if keysignPayload.coin.isNativeToken {
            let input = SolanaSigningInput.with {
                $0.transferTransaction = SolanaTransfer.with {
                    $0.recipient = toAddress.description
                    $0.value = UInt64(keysignPayload.toAmount)
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                }
                $0.recentBlockhash = recentBlockHash
                $0.sender = keysignPayload.coin.address
                $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                    $0.price = UInt64(priorityFee)
                }
            }
            return try input.serializedData()
        } else {
            
            // We should not create a new account association if it already has.
            // So we can can use a simple tokenTransferTransaction
            if let fromPubKey = fromAddressPubKey, let toPubKey = toAddressPubKey {
                
                let tokenTransferMessage = SolanaTokenTransfer.with {
                    $0.tokenMintAddress = keysignPayload.coin.contractAddress
                    $0.senderTokenAddress = fromPubKey
                    $0.recipientTokenAddress = toPubKey
                    $0.amount = UInt64(keysignPayload.toAmount)
                    $0.decimals = UInt32(keysignPayload.coin.decimals)
                }
                
                let input = SolanaSigningInput.with {
                    $0.tokenTransferTransaction = tokenTransferMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = UInt64(priorityFee)
                    }
                }
                
                return try input.serializedData()
                
            } else if let fromPubKey = fromAddressPubKey {
                
                // We will need to create a new account association between the mint token and the receiver
                
                let receiverAddress = SolanaAddress(string: toAddress.description)!
                let generatedAssociatedAddress = receiverAddress.defaultTokenAddress(tokenMintAddress: keysignPayload.coin.contractAddress)
                
                guard let createdRecipientAddress = generatedAssociatedAddress else {
                    throw HelperError.runtimeError("We must have the association between the minted token and the TO address")
                }
                
                let createAndTransferTokenMessage = SolanaCreateAndTransferToken.with {
                    $0.recipientMainAddress = toAddress.description
                    $0.tokenMintAddress = keysignPayload.coin.contractAddress
                    $0.recipientTokenAddress = createdRecipientAddress
                    $0.senderTokenAddress = fromPubKey
                    $0.amount = UInt64(keysignPayload.toAmount)
                    $0.decimals = UInt32(keysignPayload.coin.decimals)
                }
                
                let input = SolanaSigningInput.with {
                    $0.createAndTransferTokenTransaction = createAndTransferTokenMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = UInt64(priorityFee)
                    }
                }
                
                return try input.serializedData()
            }
            
            throw HelperError.runtimeError("To send tokens we must have the association between the minted token and the TO address")
            
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedData: hashes)
        
        print(preSigningOutput.errorMessage)
        
        return [preSigningOutput.data.hexString]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
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
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedData: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .solana,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try SolanaSigningOutput(serializedData: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: getHashFromRawTransaction(tx:output.encoded))
        return result
    }
    
    static func getHashFromRawTransaction(tx: String) -> String {
        let sig =  Data(tx.prefix(64).utf8)
        return sig.base64EncodedString()
    }
}
