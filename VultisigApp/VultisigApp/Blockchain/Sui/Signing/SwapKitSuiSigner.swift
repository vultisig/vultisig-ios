//
//  SwapKitSuiSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built Sui programmable transaction block (PTB) bytes.
//  WalletCore's `SuiSigningInput` only exposes structured `Pay` / `PaySui`
//  flows — it can't take a serialized PTB and produce a sighash. We mirror
//  the QBTC claim's hash-and-sign pattern: compute Sui's signing digest
//  ourselves, feed it to MPC, then assemble the Sui submit-format
//  signature envelope around the resulting ed25519 signature.
//
//  Sui signing intent (from the Sui spec):
//
//    intent_message = [scope=0 (TransactionData), version=0 (V0), app=0 (Sui)]
//                     || bcs(transaction_data)
//    digest         = blake2b_32(intent_message)
//
//  SwapKit returns the BCS-serialized transaction data as a base64 string
//  (decoded into `tx_payload` by `SwapPayloadBuilder`). We prepend the three
//  intent-prefix bytes and hash with Blake2b-32. The submit-format signature
//  envelope is `[flag=0x00 ed25519, sig (64 bytes), pubkey (32 bytes)]`
//  base64-encoded — this is the `signatures[0]` argument to
//  `sui_executeTransactionBlock`. The `tx_bytes` argument to the RPC is the
//  same base64 PTB SwapKit handed us, passed verbatim.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-sui-signer")

enum SwapKitSuiSignerError: Error, LocalizedError {
    case emptyPayload
    case missingSignature(digestHex: String)
    case invalidPublicKey(String)
    case signatureVerifyFailed

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "SwapKit Sui payload is empty"
        case .missingSignature(let hex):
            return "MPC signature missing for Sui digest \(hex.prefix(16))..."
        case .invalidPublicKey(let key):
            return "Invalid Sui public key: \(key)"
        case .signatureVerifyFailed:
            return "SwapKit Sui signature verification failed"
        }
    }
}

enum SwapKitSuiSigner {

    /// Sui transaction-data intent prefix (scope=0, version=0, app=0).
    static let intentPrefix = Data([0x00, 0x00, 0x00])

    /// Ed25519 signature scheme flag in Sui's signature envelope.
    static let ed25519SchemeFlag: UInt8 = 0x00

    /// Compute the Sui signing digest (Blake2b-32 of `intent || ptb`).
    /// Returns a single-element array because every Sui transaction signs
    /// one digest. Result is hex-encoded to match the existing keysign
    /// message-hash format.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        let digest = try digest(payload: payload)
        return [digest.hexString]
    }

    /// Assemble the Sui submit-format signed transaction. `rawTransaction`
    /// is the base64 PTB; `signature` is the base64-encoded ed25519
    /// signature envelope. `transactionHash` stays empty because Sui's
    /// canonical tx digest only resolves after the RPC accepts the
    /// submission — same convention as `SuiHelper.getSignedTransaction`.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubKeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            throw SwapKitSuiSignerError.invalidPublicKey(pubKeyHex)
        }

        let digest = try digest(payload: payload)
        let provider = SignatureProvider(signatures: signatures)
        let signature = provider.getSignature(preHash: digest)
        guard !signature.isEmpty else {
            throw SwapKitSuiSignerError.missingSignature(digestHex: digest.hexString)
        }
        guard publicKey.verify(signature: signature, message: digest) else {
            throw SwapKitSuiSignerError.signatureVerifyFailed
        }

        // Envelope: [flag=0x00 ed25519, sig (64 bytes), pubkey (32 bytes)].
        var envelope = Data()
        envelope.append(Self.ed25519SchemeFlag)
        envelope.append(signature)
        envelope.append(pubKeyData)

        let unsignedBase64 = payload.txPayload.base64EncodedString()
        let signatureBase64 = envelope.base64EncodedString()
        return SignedTransactionResult(
            rawTransaction: unsignedBase64,
            transactionHash: .empty,
            signature: signatureBase64
        )
    }

    /// Sui signing digest = Blake2b-32 of `intent_prefix || ptb_bytes`. The
    /// PTB bytes are passed verbatim — SwapKit hands us already-BCS-serialized
    /// transaction data, which is exactly what the intent message wraps.
    static func digest(payload: SwapKitSwapPayload) throws -> Data {
        guard !payload.txPayload.isEmpty else {
            throw SwapKitSuiSignerError.emptyPayload
        }
        var message = Data()
        message.append(Self.intentPrefix)
        message.append(payload.txPayload)
        return Hash.blake2b(data: message, size: 32)
    }
}
