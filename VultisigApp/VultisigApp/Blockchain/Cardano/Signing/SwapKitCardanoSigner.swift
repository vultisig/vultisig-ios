//
//  SwapKitCardanoSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built Cardano CBOR transaction envelope. SwapKit
//  performs UTXO selection, change splitting, and fee computation server-
//  side; we sign the bytes verbatim so the broadcast tx_id matches the one
//  NEAR Intents tracks the route by.
//
//  Cardano signing model (Shelley-era):
//
//      tx_envelope = [
//          transaction_body,        // CBOR map — the bytes we hash
//          transaction_witness_set, // initially empty (a0) — we splice the
//                                   //   vkey witness here
//          is_valid,                // true (f5)
//          auxiliary_data           // null (f6)
//      ]
//
//      tx_id  = Blake2b-256(cbor(transaction_body))
//      digest = tx_id  (same primitive; what MPC Ed25519 signs)
//      witness_set = { 0: [[vkey_32, signature_64]] }
//
//  CBOR walking: we don't pull in a CBOR library — Cardano envelopes are
//  small, definite-length, well-formed by construction, and we only need to
//  measure the byte length of items 0..3. A tiny walker (60 lines) suffices
//  and avoids a new SwiftPM dependency. The existing `CardanoSignedTxBuilder`
//  takes care of the CBOR length-prefix encoding for the vkey + sig bytes.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-cardano-signer")

enum SwapKitCardanoSignerError: Error, LocalizedError {
    case emptyPayload
    case truncated
    case malformedEnvelope(String)
    case missingSignature(digestHex: String)
    case invalidPublicKey(String)
    case signatureVerifyFailed
    case witnessAssembly(String)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "SwapKit Cardano payload is empty"
        case .truncated:
            return "SwapKit Cardano CBOR is truncated"
        case .malformedEnvelope(let detail):
            return "SwapKit Cardano CBOR envelope is malformed: \(detail)"
        case .missingSignature(let hex):
            return "MPC signature missing for Cardano digest \(hex.prefix(16))..."
        case .invalidPublicKey(let key):
            return "Invalid Cardano public key: \(key)"
        case .signatureVerifyFailed:
            return "SwapKit Cardano signature verification failed"
        case .witnessAssembly(let detail):
            return "Failed to assemble SwapKit Cardano witness: \(detail)"
        }
    }
}

enum SwapKitCardanoSigner {

    /// Compute the Cardano signing digest = `Blake2b-256(cbor(transaction_body))`.
    /// Cardano signs the body bytes only (not the whole envelope), so we walk
    /// the top-level array, slice item 0 verbatim, and hash. Returns one
    /// hex-encoded digest — Cardano transactions sign a single hash regardless
    /// of input count.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        let digest = try digest(payload: payload)
        return [digest.hexString]
    }

    /// Assemble the signed broadcast envelope: keep items 0/2/3 verbatim,
    /// replace item 1 (witness_set) with `{ 0: [[vkey, sig]] }`. The body
    /// bytes are re-emitted byte-for-byte; re-encoding would risk changing
    /// CBOR integer widths or map ordering and invalidate the signature.
    /// `rawTransaction` is the broadcast hex (the same wire format
    /// `CardanoService.broadcastTransaction(signedTransaction:)` consumes);
    /// `transactionHash` is the Cardano tx_id (== Blake2b-256(body)).
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubKeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            throw SwapKitCardanoSignerError.invalidPublicKey(pubKeyHex)
        }

        let parsed = try parseEnvelope(payload.txPayload)
        let body = parsed.body
        let digestBytes = Hash.blake2b(data: body, size: 32)

        let provider = SignatureProvider(signatures: signatures)
        let signature = provider.getSignature(preHash: digestBytes)
        guard !signature.isEmpty else {
            throw SwapKitCardanoSignerError.missingSignature(digestHex: digestBytes.hexString)
        }
        guard publicKey.verify(signature: signature, message: digestBytes) else {
            throw SwapKitCardanoSignerError.signatureVerifyFailed
        }

        let assembled: Data
        do {
            assembled = try assembleSignedTransaction(
                parsed: parsed,
                publicKey: pubKeyData,
                signature: signature
            )
        } catch let err as CardanoSignedTxBuilderError {
            throw SwapKitCardanoSignerError.witnessAssembly("\(err)")
        }

        return SignedTransactionResult(
            rawTransaction: assembled.hexString,
            transactionHash: digestBytes.hexString
        )
    }

    /// Exposed for tests so callers can pin the Blake2b-256 digest of a
    /// known-good envelope.
    static func digest(payload: SwapKitSwapPayload) throws -> Data {
        let parsed = try parseEnvelope(payload.txPayload)
        return Hash.blake2b(data: parsed.body, size: 32)
    }

    /// Exposed for tests so callers can verify the broadcast-format envelope
    /// against a known sig + vkey without going through MPC.
    static func assembleSignedTransaction(
        unsignedCbor: Data,
        signature: Data,
        verificationKey: Data
    ) throws -> Data {
        let parsed = try parseEnvelope(unsignedCbor)
        return try assembleSignedTransaction(
            parsed: parsed,
            publicKey: verificationKey,
            signature: signature
        )
    }

    // MARK: - CBOR walking

    /// Result of walking the top-level array. We keep only the byte ranges we
    /// need to re-emit during assembly; the body bytes are sliced out for
    /// hashing.
    private struct ParsedEnvelope {
        let body: Data
        let isValid: Data
        let auxData: Data
    }

    private static func parseEnvelope(_ data: Data) throws -> ParsedEnvelope {
        guard !data.isEmpty else { throw SwapKitCardanoSignerError.emptyPayload }
        guard data[data.startIndex] == 0x84 else {
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "expected top-level array(4) (0x84), got 0x\(String(data[data.startIndex], radix: 16))"
            )
        }

        var offset = 1
        let bodyLen = try cborItemLength(data: data, offset: offset)
        let body = data[(data.startIndex + offset)..<(data.startIndex + offset + bodyLen)]
        offset += bodyLen

        let wsLen = try cborItemLength(data: data, offset: offset)
        offset += wsLen

        let ivLen = try cborItemLength(data: data, offset: offset)
        let isValid = data[(data.startIndex + offset)..<(data.startIndex + offset + ivLen)]
        offset += ivLen

        let adLen = try cborItemLength(data: data, offset: offset)
        let auxData = data[(data.startIndex + offset)..<(data.startIndex + offset + adLen)]
        offset += adLen

        // Cardano envelopes are well-formed by construction; trailing bytes
        // signal a malformed payload, not forward compatibility.
        guard offset == data.count else {
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "trailing bytes after array(4): consumed \(offset), total \(data.count)"
            )
        }

        return ParsedEnvelope(
            body: Data(body),
            isValid: Data(isValid),
            auxData: Data(auxData)
        )
    }

    /// Compute the byte length of the CBOR data item at `offset`. Handles
    /// definite-length encodings only — Cardano transactions never use
    /// indefinite-length items, so an indefinite header is a malformed
    /// envelope.
    private static func cborItemLength(data: Data, offset: Int) throws -> Int {
        guard offset < data.count else { throw SwapKitCardanoSignerError.truncated }
        let start = offset
        var cursor = offset
        let head = data[data.startIndex + cursor]
        cursor += 1
        let majorType = head >> 5
        let additionalInfo = head & 0x1f

        let argument: UInt64
        switch additionalInfo {
        case 0...23:
            argument = UInt64(additionalInfo)
        case 24:
            guard cursor < data.count else { throw SwapKitCardanoSignerError.truncated }
            argument = UInt64(data[data.startIndex + cursor]); cursor += 1
        case 25:
            argument = UInt64(try readBE(data: data, offset: &cursor, bytes: 2))
        case 26:
            argument = UInt64(try readBE(data: data, offset: &cursor, bytes: 4))
        case 27:
            argument = try readBE(data: data, offset: &cursor, bytes: 8)
        default:
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "indefinite-length or reserved CBOR additional-info: \(additionalInfo)"
            )
        }

        switch majorType {
        case 0, 1, 7:
            // unsigned int / negative int / simple-or-float — header only.
            return cursor - start
        case 2, 3:
            // byte string / text string — header + `argument` bytes payload.
            let payload = Int(argument)
            guard data.startIndex + cursor + payload <= data.endIndex else {
                throw SwapKitCardanoSignerError.truncated
            }
            return (cursor - start) + payload
        case 4:
            // array: `argument` items follow.
            var sub = cursor
            for _ in 0..<argument {
                let itemLen = try cborItemLength(data: data, offset: sub)
                sub += itemLen
            }
            return sub - start
        case 5:
            // map: `argument` (key, value) pairs follow.
            var sub = cursor
            for _ in 0..<argument {
                let keyLen = try cborItemLength(data: data, offset: sub)
                sub += keyLen
                let valLen = try cborItemLength(data: data, offset: sub)
                sub += valLen
            }
            return sub - start
        case 6:
            // tag: header + one tagged item.
            let inner = try cborItemLength(data: data, offset: cursor)
            return (cursor - start) + inner
        default:
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "unknown CBOR major type: \(majorType)"
            )
        }
    }

    private static func readBE(data: Data, offset: inout Int, bytes: Int) throws -> UInt64 {
        guard data.startIndex + offset + bytes <= data.endIndex else {
            throw SwapKitCardanoSignerError.truncated
        }
        var value: UInt64 = 0
        for _ in 0..<bytes {
            value = (value << 8) | UInt64(data[data.startIndex + offset])
            offset += 1
        }
        return value
    }

    // MARK: - Witness assembly

    /// Internal entry point shared by `compileSignedTransaction` and the
    /// public test seam `assembleSignedTransaction(unsignedCbor:...)`.
    private static func assembleSignedTransaction(
        parsed: ParsedEnvelope,
        publicKey: Data,
        signature: Data
    ) throws -> Data {
        guard publicKey.count == CardanoSignedTxBuilder.publicKeyLength else {
            throw CardanoSignedTxBuilderError.invalidPublicKeyLength(publicKey.count)
        }
        guard signature.count == CardanoSignedTxBuilder.signatureLength else {
            throw CardanoSignedTxBuilderError.invalidSignatureLength(signature.count)
        }

        // witness_set = { 0: [ [vkey, sig] ] }
        //   a1 00 81 82 <bytes(vkey)> <bytes(sig)>
        // Length-prefix encoding for the 32-byte vkey + 64-byte sig is the
        // same one `CardanoSignedTxBuilder.cborBytes` uses for the send path.
        var witness = Data()
        witness.append(0xA1) // map(1)
        witness.append(0x00) // key: uint(0)
        witness.append(0x81) // array(1)
        witness.append(0x82) // array(2)
        witness.append(CardanoSignedTxBuilder.cborBytes(publicKey))
        witness.append(CardanoSignedTxBuilder.cborBytes(signature))

        var output = Data()
        output.append(0x84) // array(4)
        output.append(parsed.body)
        output.append(witness)
        output.append(parsed.isValid)
        output.append(parsed.auxData)
        return output
    }
}
