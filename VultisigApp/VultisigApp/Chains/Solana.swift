//
//  Solana.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt
#if os(iOS)
import UIKit
#endif

enum SolanaHelper {
    
    static let defaultFeeInLamports: BigInt = 1000000 //0.001
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SOL" else {
            throw HelperError.runtimeError("coin is not SOL")
        }
        guard case .Solana(let recentBlockHash, _, let fromAddressPubKey, let toAddressPubKey, let tokenProgramId) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get to address")
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .solana) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        let priorityFeePrice = 1_000_000; // Turbo fee in lamports, around 5 cents
        let priorityFeeLimit = UInt32(100_000);
        
        if keysignPayload.coin.isNativeToken {
            let input = SolanaSigningInput.with {
                $0.transferTransaction = SolanaTransfer.with {
                    $0.recipient = toAddress.description
                    $0.value = UInt64(keysignPayload.toAmount)
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                }
                $0.recentBlockhash = recentBlockHash // DKLS should fix it. Using the same, since fetching the latest block hash won't match with Win and Android
                $0.sender = keysignPayload.coin.address
                $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                    $0.price = UInt64(priorityFeePrice)
                }
                $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                    $0.limit = priorityFeeLimit
                }
            }
            return try input.serializedData()
        } else {
            
            // We should not create a new account association if it already has.
            // So we can can use a simple tokenTransferTransaction
            if let fromPubKey = fromAddressPubKey, !fromPubKey.isEmpty, let toPubKey = toAddressPubKey, !toPubKey.isEmpty {
                
                let tokenTransferMessage = SolanaTokenTransfer.with {
                    $0.tokenMintAddress = keysignPayload.coin.contractAddress
                    $0.senderTokenAddress = fromPubKey
                    $0.recipientTokenAddress = toPubKey
                    $0.amount = UInt64(keysignPayload.toAmount)
                    $0.decimals = UInt32(keysignPayload.coin.decimals)
                    $0.tokenProgramID = tokenProgramId ? SolanaTokenProgramId.token2022Program : SolanaTokenProgramId.tokenProgram
                }
                
                let input = SolanaSigningInput.with {
                    $0.tokenTransferTransaction = tokenTransferMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = UInt64(priorityFeePrice)
                    }
                    $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                        $0.limit = priorityFeeLimit
                    }
                }
                
                return try input.serializedData()
                
            } else if let fromPubKey = fromAddressPubKey, !fromPubKey.isEmpty {
                
                print("\n=== CREATING NEW TOKEN ACCOUNT ===")
                #if os(iOS)
                print("Device: \(UIDevice.current.name)")
                #else
                print("Device: macOS")
                #endif
                print("Time: \(Date())")
                print("Token Program: \(tokenProgramId ? "Token-2022" : "SPL Token")")
                print("Mint: \(keysignPayload.coin.contractAddress)")
                print("Recipient: \(toAddress.description)")
                
                // Create new account association for either SPL or Token-2022
                let receiverAddress = SolanaAddress(string: toAddress.description)!
                
                let generatedAssociatedAddress: String?
                if tokenProgramId {
                    // Use Token-2022 specific method
                    generatedAssociatedAddress = receiverAddress.token2022Address(tokenMintAddress: keysignPayload.coin.contractAddress)
                    print("Using token2022Address method")
                } else {
                    // Use standard SPL token method
                    generatedAssociatedAddress = receiverAddress.defaultTokenAddress(tokenMintAddress: keysignPayload.coin.contractAddress)
                    print("Using defaultTokenAddress method")
                }
                
                print("Generated address: \(generatedAssociatedAddress ?? "nil")")
                print("==================================\n")
                
                guard let createdRecipientAddress = generatedAssociatedAddress else {
                    throw HelperError.runtimeError("Failed to generate associated token address for recipient")
                }
                
                let createAndTransferTokenMessage = SolanaCreateAndTransferToken.with {
                    $0.recipientMainAddress = toAddress.description
                    $0.tokenMintAddress = keysignPayload.coin.contractAddress
                    $0.recipientTokenAddress = createdRecipientAddress
                    $0.senderTokenAddress = fromPubKey
                    $0.amount = UInt64(keysignPayload.toAmount)
                    $0.decimals = UInt32(keysignPayload.coin.decimals)
                    $0.tokenProgramID = tokenProgramId ? SolanaTokenProgramId.token2022Program : SolanaTokenProgramId.tokenProgram
                }
                
                print("\n=== CREATE AND TRANSFER MESSAGE ===")
                print("Recipient main: \(toAddress.description)")
                print("Token mint: \(keysignPayload.coin.contractAddress)")
                print("Recipient token account: \(createdRecipientAddress)")
                print("Sender token account: \(fromPubKey)")
                print("Amount: \(keysignPayload.toAmount)")
                print("Decimals: \(keysignPayload.coin.decimals)")
                print("Token program ID: \(createAndTransferTokenMessage.tokenProgramID)")
                print("==================================\n")
                
                let input = SolanaSigningInput.with {
                    $0.createAndTransferTokenTransaction = createAndTransferTokenMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = UInt64(priorityFeePrice)
                    }
                    $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                        $0.limit = priorityFeeLimit
                    }
                }
                
                let serializedData = try input.serializedData()
                print("Serialized input data length: \(serializedData.count)")
                
                return serializedData
            }
            
            throw HelperError.runtimeError("SPL token transfer failed: sender's associated token account not found. Please ensure you have this token in your wallet.")
            
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let imageHash = try SolanaHelper.getPreSignedImageHash(inputData: inputData)
        return imageHash
    }

    static func getPreSignedImageHash(inputData: Data) throws -> [String] {
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)
        
        print("\n=== PRE-SIGNING OUTPUT ===")
        print("Error message: \(preSigningOutput.errorMessage.isEmpty ? "None" : preSigningOutput.errorMessage)")
        print("Hash to sign: \(preSigningOutput.data.hexString)")
        print("=========================\n")
        
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
        guard let _ = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)

        let result = try SolanaHelper.getSignedTransaction(
            vaultHexPubKey: vaultHexPubKey,
            inputData: inputData,
            signatures: signatures
        )

        return result
    }

    static func getSignedTransaction(vaultHexPubKey: String, inputData: Data, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {

        print("\n=== SOLANA TRANSACTION SIGNING ===")
        print("Time: \(Date())")
        #if os(iOS)
        print("Device: \(UIDevice.current.name)")
        #else
        print("Device: macOS")
        #endif
        print("Vault public key: \(vaultHexPubKey)")
        print("Input data length: \(inputData.count)")
        
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }

        print("Getting pre-image hashes...")
        let hashStartTime = Date()
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)
        print("Pre-image hash generated in: \(String(format: "%.3f", Date().timeIntervalSince(hashStartTime))) seconds")
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        
        print("Signature length: \(signature.count)")
        print("Verifying signature...")
        let verifyStartTime = Date()

        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            print("Signature verification FAILED!")
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        print("Signature verified in: \(String(format: "%.3f", Date().timeIntervalSince(verifyStartTime))) seconds")

        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        
        print("Compiling transaction with signatures...")
        let compileStartTime = Date()
        
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .solana,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try SolanaSigningOutput(serializedBytes: compileWithSignature)
        
        print("Transaction compiled in: \(String(format: "%.3f", Date().timeIntervalSince(compileStartTime))) seconds")
        print("Total signing time: \(String(format: "%.3f", Date().timeIntervalSince(hashStartTime))) seconds")
        print("==================================\n")
        
        print("\n=== COMPILED TRANSACTION ===")
        print("Time: \(Date())")
        print("Output error: \(output.errorMessage.isEmpty ? "None" : output.errorMessage)")
        print("Encoded transaction length: \(output.encoded.count)")
        print("Transaction hash: \(getHashFromRawTransaction(tx:output.encoded))")
        print("===========================\n")
        
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: getHashFromRawTransaction(tx:output.encoded))

        return result
    }

    static func getHashFromRawTransaction(tx: String) -> String {
        let sig =  Data(tx.prefix(64).utf8)
        return sig.base64EncodedString()
    }
}
