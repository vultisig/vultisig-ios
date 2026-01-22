//
//  Solana.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum SolanaHelper {

    static let defaultFeeInLamports: BigInt = 1000000 // 0.001
    static let priorityFeePrice: UInt64 = 1_000_000 // Priority fee price in lamports
    static let priorityFeeLimit: BigInt = 100_000 // Priority fee compute unit limit

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SOL" else {
            throw HelperError.runtimeError("coin is not SOL")
        }
        guard case .Solana(let recentBlockHash, _, let priorityLimit, let fromAddressPubKey, let toAddressPubKey, let tokenProgramId) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get to address")
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .solana) else {
            throw HelperError.runtimeError("fail to get to address")
        }

        // Use default priority limit if not provided (backward compatibility)
        let effectivePriorityLimit = priorityLimit > 0 ? priorityLimit : SolanaHelper.priorityFeeLimit

        guard effectivePriorityLimit <= UInt32.max else {
            throw HelperError.runtimeError("priorityLimit exceeds UInt32 bounds: \(effectivePriorityLimit)")
        }
        let priorityFeeLimitValue = UInt32(truncatingIfNeeded: effectivePriorityLimit)

        if keysignPayload.coin.isNativeToken {
            let input = SolanaSigningInput.with {
                $0.v0Msg = true
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
                    $0.price = SolanaHelper.priorityFeePrice
                }
                $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                    $0.limit = priorityFeeLimitValue
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
                    $0.v0Msg = true
                    $0.tokenTransferTransaction = tokenTransferMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = SolanaHelper.priorityFeePrice
                    }
                    $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                        $0.limit = priorityFeeLimitValue
                    }
                }

                return try input.serializedData()

            } else if let fromPubKey = fromAddressPubKey, !fromPubKey.isEmpty {

                // Create new account association for either SPL or Token-2022
                let receiverAddress = SolanaAddress(string: toAddress.description)!

                let generatedAssociatedAddress: String?
                if tokenProgramId {
                    // Use Token-2022 specific method
                    generatedAssociatedAddress = receiverAddress.token2022Address(tokenMintAddress: keysignPayload.coin.contractAddress)
                } else {
                    // Use standard SPL token method
                    generatedAssociatedAddress = receiverAddress.defaultTokenAddress(tokenMintAddress: keysignPayload.coin.contractAddress)
                }

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

                let input = SolanaSigningInput.with {
                    $0.v0Msg = true
                    $0.createAndTransferTokenTransaction = createAndTransferTokenMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = SolanaHelper.priorityFeePrice
                    }
                    $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                        $0.limit = priorityFeeLimitValue
                    }
                }

                return try input.serializedData()
            }

            throw HelperError.runtimeError("SPL token transfer failed: sender's associated token account not found. Please ensure you have this token in your wallet.")

        }
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        // Handle SignSolana (raw transactions)
        if let signSolana = keysignPayload.signSolana {
            var allHashes: [String] = []
            for base64Tx in signSolana.rawTransactions {
                let hashes = try getPreSignedImageHashForRaw(base64Transaction: base64Tx)
                allHashes.append(contentsOf: hashes)
            }
            return allHashes
        }

        // Regular Solana transaction flow
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let imageHash = try SolanaHelper.getPreSignedImageHash(inputData: inputData)
        return imageHash
    }

    static func getPreSignedImageHash(inputData: Data) throws -> [String] {
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)

        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        // Handle SignSolana (raw transactions)
        if let signSolana = keysignPayload.signSolana {
            let hexPubKey = keysignPayload.coin.hexPublicKey

            // For multiple transactions, return the first one
            // TODO: Handle multiple transactions properly if needed
            guard let firstTx = signSolana.rawTransactions.first else {
                throw HelperError.runtimeError("No transactions to sign")
            }

            return try signRawTransaction(
                coinHexPubKey: hexPubKey,
                base64Transaction: firstTx,
                signatures: signatures
            )
        }

        // Regular transaction flow
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let _ = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)

        let result = try SolanaHelper.getSignedTransaction(
            coinHexPubKey: coinHexPublicKey,
            inputData: inputData,
            signatures: signatures
        )

        return result
    }

    static func getSignedTransaction(coinHexPubKey: String, inputData: Data, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {

        guard let pubkeyData = Data(hexString: coinHexPubKey) else {
            throw HelperError.runtimeError("public key \(coinHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPubKey) is invalid")
        }

        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)

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
        let output = try SolanaSigningOutput(serializedBytes: compileWithSignature)

        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: getHashFromRawTransaction(tx: output.encoded))

        return result
    }

    // MARK: - Raw Transaction Signing

    static func getPreSignedImageHashForRaw(base64Transaction: String) throws -> [String] {
        guard let txData = Data(base64Encoded: base64Transaction) else {
            throw HelperError.runtimeError("Invalid base64 transaction")
        }

        // Decode the transaction using TransactionDecoder
        let decodedData = TransactionDecoder.decode(coinType: .solana, encodedTx: txData)
        let decodedOutput = try SolanaDecodingTransactionOutput(serializedBytes: decodedData)

        if decodedOutput.errorMessage.isNotEmpty {
            throw HelperError.runtimeError(decodedOutput.errorMessage)
        }

        // Wrap in SolanaSigningInput with rawMessage
        let input = SolanaSigningInput.with {
            $0.rawMessage = decodedOutput.transaction
        }

        let inputData = try input.serializedData()

        // Get pre-image hashes
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)

        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        return [preSigningOutput.data.hexString]
    }

    static func signRawTransaction(
        coinHexPubKey: String,
        base64Transaction: String,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        // 1. Validate inputs
        guard let pubkeyData = Data(hexString: coinHexPubKey) else {
            throw HelperError.runtimeError("Invalid public key: \(coinHexPubKey)")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("Invalid public key format")
        }
        guard let txData = Data(base64Encoded: base64Transaction) else {
            throw HelperError.runtimeError("Invalid base64 transaction")
        }

        // 2. Decode the transaction using TransactionDecoder
        let decodedData = TransactionDecoder.decode(coinType: .solana, encodedTx: txData)
        let decodedOutput = try SolanaDecodingTransactionOutput(serializedBytes: decodedData)

        if decodedOutput.errorMessage.isNotEmpty {
            throw HelperError.runtimeError(decodedOutput.errorMessage)
        }

        // 3. Wrap in SolanaSigningInput with rawMessage
        let input = SolanaSigningInput.with {
            $0.rawMessage = decodedOutput.transaction
        }

        let inputData = try input.serializedData()

        // 4. Get pre-image hash
        let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
        let preSigningOutput = try SolanaPreSigningOutput(serializedBytes: hashes)

        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        // 5. Get signature from MPC results
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)

        // 6. Verify signature
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("Signature verification failed")
        }

        // 7. Compile with TransactionCompiler.compileWithSignatures
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)

        let compiled = TransactionCompiler.compileWithSignatures(
            coinType: .solana,
            txInputData: inputData,
            signatures: allSignatures,
            publicKeys: publicKeys
        )

        // 8. Return SignedTransactionResult
        let output = try SolanaSigningOutput(serializedBytes: compiled)

        return SignedTransactionResult(
            rawTransaction: output.encoded,
            transactionHash: getHashFromRawTransaction(tx: output.encoded)
        )
    }

    static func getHashFromRawTransaction(tx: String) -> String {
        let sig =  Data(tx.prefix(64).utf8)
        return sig.base64EncodedString()
    }

    static func getZeroSignedTransaction(keysignPayload: KeysignPayload) throws -> String {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let publicKey = PublicKey(data: Data(hex: coinHexPublicKey), type: PublicKeyType.ed25519) else {
            throw HelperError.runtimeError("Not a valid public key")
        }
        let input = try getPreSignedInputData(keysignPayload: keysignPayload)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        allSignatures.add(data: Data(hex: Array.init(repeating: "0", count: 128).joined()))
        publicKeys.add(data: publicKey.data)
        let compiledWithSignature = TransactionCompiler.compileWithSignatures(
            coinType: .solana,
            txInputData: input,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try SolanaSigningOutput(serializedBytes: compiledWithSignature)
        return output.encoded
    }
}
