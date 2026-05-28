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
    static let defaultPriorityFeePrice: UInt64 = 1_000_000 // Fallback priority fee price in microlamports
    static let priorityFeeLimit: BigInt = 100_000 // Priority fee compute unit limit
    /// Rent-exempt reserve for a new SPL Associated Token Account (~0.00203928 SOL).
    /// Required when the recipient has no ATA and we create one alongside the transfer.
    static let ataRentLamports: BigInt = 2_039_280

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SOL" else {
            throw HelperError.runtimeError("coin is not SOL")
        }
        guard case .Solana(let recentBlockHash, let priorityFee, let priorityLimit, let fromAddressPubKey, let toAddressPubKey, let tokenProgramId) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get to address")
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .solana) else {
            throw HelperError.runtimeError("fail to get to address")
        }

        // Use dynamic priority fee if provided, otherwise fall back to default
        let effectivePriorityFeePrice = priorityFee > 0 ? UInt64(priorityFee) : SolanaHelper.defaultPriorityFeePrice

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
                    $0.price = effectivePriorityFeePrice
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
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                }

                let input = SolanaSigningInput.with {
                    $0.v0Msg = true
                    $0.tokenTransferTransaction = tokenTransferMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = effectivePriorityFeePrice
                    }
                    $0.priorityFeeLimit = SolanaPriorityFeeLimit.with {
                        $0.limit = priorityFeeLimitValue
                    }
                }

                return try input.serializedData()

            } else if let fromPubKey = fromAddressPubKey, !fromPubKey.isEmpty {

                // Recipient has no Associated Token Account yet. Derive the deterministic ATA
                // and let TrustWalletCore emit a `createAssociatedTokenAccount` instruction
                // alongside the SPL transfer in a single transaction.
                guard let receiverAddress = SolanaAddress(string: toAddress.description) else {
                    throw HelperError.runtimeError("Invalid recipient Solana address")
                }

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
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                }

                let input = SolanaSigningInput.with {
                    $0.v0Msg = true
                    $0.createAndTransferTokenTransaction = createAndTransferTokenMessage
                    $0.recentBlockhash = recentBlockHash
                    $0.sender = keysignPayload.coin.address
                    $0.priorityFeePrice = SolanaPriorityFeePrice.with {
                        $0.price = effectivePriorityFeePrice
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
            guard signSolana.rawTransactions.count == 1 else {
                throw HelperError.runtimeError("signSolana with multiple raw transactions is not supported")
            }
            let hexPubKey = keysignPayload.coin.hexPublicKey

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

        guard let txData = Data(base64Encoded: output.encoded) else {
            throw HelperError.runtimeError("Failed to decode signed Solana transaction")
        }
        let result = SignedTransactionResult(
            rawTransaction: output.encoded,
            transactionHash: try getHashFromRawTransaction(txData: txData)
        )

        return result
    }

    // When a dApp swap carries both a swap quote and raw signSolana bytes, the raw
    // bytes take priority — they already contain the correct blockhash.
    static func getPreSignedImageHash(
        swapPayload: GenericSwapPayload,
        keysignPayload: KeysignPayload
    ) throws -> [String] {
        if keysignPayload.signSolana != nil {
            return try getPreSignedImageHash(keysignPayload: keysignPayload)
        }
        return try SolanaSwaps().getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: keysignPayload)
    }

    static func getSignedTransaction(
        swapPayload: GenericSwapPayload,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        if keysignPayload.signSolana != nil {
            return try getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
        }
        return try SolanaSwaps().getSignedTransaction(swapPayload: swapPayload, keysignPayload: keysignPayload, signatures: signatures)
    }

    // MARK: - Raw Transaction Signing

    // For dApp-supplied raw transactions we sign the message bytes directly
    // instead of routing through SolanaSigningInput.rawMessage +
    // TransactionCompiler. The round-trip through WalletCore's proto re-encoder
    // is sensitive to WalletCore version differences between platforms — even
    // a one-byte drift in the re-encoded message produces a different pre-image
    // hash, which breaks Secure Vault co-signing (other party computes a
    // different hash, the setup-message equality check throws, no TSS messages
    // are ever emitted). For Solana, ed25519 signs the wire-format message
    // verbatim, so extracting it directly is canonical and cross-platform safe.

    static func getPreSignedImageHashForRaw(base64Transaction: String) throws -> [String] {
        guard let txData = Data(base64Encoded: base64Transaction) else {
            throw HelperError.runtimeError("Invalid base64 transaction")
        }
        let messageBytes = try extractSolanaMessageBytes(from: txData).message
        return [messageBytes.hexString]
    }

    static func signRawTransaction(
        coinHexPubKey: String,
        base64Transaction: String,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPubKey) else {
            throw HelperError.runtimeError("Invalid public key: \(coinHexPubKey)")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("Invalid public key format")
        }
        guard let txData = Data(base64Encoded: base64Transaction) else {
            throw HelperError.runtimeError("Invalid base64 transaction")
        }

        let parsed = try extractSolanaMessageBytes(from: txData)

        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: parsed.message)

        guard publicKey.verify(signature: signature, message: parsed.message) else {
            throw HelperError.runtimeError("Signature verification failed")
        }

        // Splice the signature into the original transaction at signer index 0
        // (the dApp builds tx with the user as fee payer == first signer; any
        // other signature slots stay as the dApp-provided placeholders).
        var signedTx = txData
        let sigRange = parsed.firstSignatureOffset..<(parsed.firstSignatureOffset + 64)
        guard sigRange.upperBound <= signedTx.count else {
            throw HelperError.runtimeError("Transaction too short to place signature")
        }
        signedTx.replaceSubrange(sigRange, with: signature)

        let encoded = signedTx.base64EncodedString()
        return SignedTransactionResult(
            rawTransaction: encoded,
            transactionHash: try getHashFromRawTransaction(txData: signedTx)
        )
    }

    /// Strip the `[shortvec(numSigs)][numSigs × 64-byte sig]` envelope and
    /// return the underlying Solana message bytes plus the offset of the first
    /// signature slot (for later splice-in).
    private static func extractSolanaMessageBytes(from txData: Data) throws -> (firstSignatureOffset: Int, message: Data) {
        var offset = 0
        var numSigs = 0
        var shift = 0
        // Solana compact-u16 (shortvec) decode: 7 bits per byte, high bit = continuation.
        while offset < txData.count {
            let byte = txData[txData.startIndex + offset]
            numSigs |= Int(byte & 0x7F) << shift
            offset += 1
            if (byte & 0x80) == 0 { break }
            shift += 7
            if shift > 14 {
                throw HelperError.runtimeError("Invalid shortvec for signature count")
            }
        }
        guard numSigs >= 1 else {
            throw HelperError.runtimeError("Transaction declares no signatures")
        }
        let firstSignatureOffset = offset
        let messageOffset = offset + numSigs * 64
        guard messageOffset < txData.count else {
            throw HelperError.runtimeError("Transaction too short for declared signature count (\(numSigs))")
        }
        let message = txData.subdata(in: (txData.startIndex + messageOffset)..<txData.endIndex)
        return (firstSignatureOffset, message)
    }

    static func getHashFromRawTransaction(txData: Data) throws -> String {
        let parsed = try extractSolanaMessageBytes(from: txData)
        let sigEnd = parsed.firstSignatureOffset + 64
        guard sigEnd <= txData.count else {
            throw HelperError.runtimeError("Transaction too short to extract signature")
        }
        let sigBytes = txData.subdata(in: (txData.startIndex + parsed.firstSignatureOffset)..<(txData.startIndex + sigEnd))
        return Base58.encodeNoCheck(data: sigBytes)
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
