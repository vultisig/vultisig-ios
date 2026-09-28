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

import BigInt
import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Log.chain.other

enum SwapKitCardanoSignerError: Error, LocalizedError {
    case emptyPayload
    case truncated
    case malformedEnvelope(String)
    case missingSignature(digestHex: String)
    case invalidPublicKey(String)
    case signatureVerifyFailed
    case witnessAssembly(String)
    case disallowedBodyField(UInt64)
    case missingOutputs
    case missingFee
    case feeExceedsCeiling(UInt64)
    case tooManyExternalOutputs
    case depositNotPlainADA
    case depositExceedsQuote(lovelace: UInt64)

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
        case .disallowedBodyField(let key):
            return "SwapKit Cardano body carries field \(key), which a plain payment never uses; refusing to sign"
        case .missingOutputs:
            return "SwapKit Cardano body has no outputs"
        case .missingFee:
            return "SwapKit Cardano body has no fee"
        case .feeExceedsCeiling(let fee):
            return "SwapKit Cardano fee \(fee) lovelace exceeds the \(SwapKitCardanoSigner.maxFeeLovelace) ceiling"
        case .tooManyExternalOutputs:
            return "SwapKit Cardano body pays more than one output outside the vault"
        case .depositNotPlainADA:
            return "SwapKit Cardano deposit output must carry plain ADA only"
        case .depositExceedsQuote(let lovelace):
            return "SwapKit Cardano deposit \(lovelace) lovelace exceeds the quoted swap amount; refusing to sign"
        }
    }
}

enum SwapKitCardanoSigner {

    /// Compute the Cardano signing digest = `Blake2b-256(cbor(transaction_body))`.
    /// Cardano signs the body bytes only (not the whole envelope), so we walk
    /// the top-level array, slice item 0 verbatim, and hash. Returns one
    /// hex-encoded digest — Cardano transactions sign a single hash regardless
    /// of input count.
    ///
    /// - Parameter vaultPubKeyEdDSA: the vault's own EdDSA public key, read
    ///   off the verifying device's local `Vault` — never a field from
    ///   `payload`, which for a peer-relayed keysign is proto-deserialized
    ///   from the counterparty and therefore untrusted. Used to check that
    ///   outputs pay back to the vault's own address before we sign anything.
    static func preSigningHashes(payload: SwapKitSwapPayload, vaultPubKeyEdDSA: String) throws -> [String] {
        guard let vaultPubKeyData = Data(hexString: vaultPubKeyEdDSA), vaultPubKeyData.count == 32 else {
            throw SwapKitCardanoSignerError.invalidPublicKey(vaultPubKeyEdDSA)
        }
        let parsed = try parseEnvelope(payload.txPayload)
        try verifyBody(parsed.body, fromAmount: payload.fromAmount, vaultPublicKey: vaultPubKeyData)
        let digestBytes = Hash.blake2b(data: parsed.body, size: 32)
        return [digestBytes.hexString]
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
        try verifyBody(body, fromAmount: payload.fromAmount, vaultPublicKey: pubKeyData)
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
    /// known-good envelope. Pure envelope hashing — no body-content
    /// verification, unlike `preSigningHashes`/`compileSignedTransaction`.
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

    // MARK: - Body verification

    /// Decodes the transaction body before signing it. Neither device's
    /// Verify screen reads the body, so it must be one the displayed quote
    /// implies: a plain payment spending the vault's UTXOs, where every
    /// output pays back to the vault except a single ADA-only deposit of at
    /// most `fromAmount`, and the fee is bounded. Fields a plain payment
    /// never carries (certificates, withdrawals, minting, collateral,
    /// required signers, governance) are refused. The deposit address itself
    /// isn't pinned: SwapKit's on-chain deposit address differs from its
    /// declared `targetAddress`.
    ///
    /// Ports `vultisig-android`'s `SwapKitCardanoSigner.verifyBody` rule for
    /// rule so iOS and Android refuse exactly the same payloads.
    private static func verifyBody(_ body: Data, fromAmount: BigInt, vaultPublicKey: Data) throws {
        let vaultAddress = try vaultEnterpriseAddress(publicKey: vaultPublicKey)
        var offset = 0
        let mapArgument = try readMapSize(data: body, offset: &offset)
        guard let mapSize = Int(exactly: mapArgument) else {
            throw SwapKitCardanoSignerError.malformedEnvelope("body map size is too large")
        }

        var outputsSeen = false
        var fee: UInt64?
        for _ in 0..<mapSize {
            let key = try readUInt(data: body, offset: &offset)
            switch key {
            case bodyOutputsKey:
                try verifyOutputs(data: body, offset: &offset, vaultAddress: vaultAddress, fromAmount: fromAmount)
                outputsSeen = true
            case bodyFeeKey:
                fee = try readUInt(data: body, offset: &offset)
            case _ where passiveBodyKeys.contains(key):
                offset += try cborItemLength(data: body, offset: offset)
            default:
                throw SwapKitCardanoSignerError.disallowedBodyField(key)
            }
        }

        guard offset == body.count else {
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "body has trailing bytes: consumed \(offset), total \(body.count)"
            )
        }
        guard outputsSeen else { throw SwapKitCardanoSignerError.missingOutputs }
        guard let signedFee = fee else { throw SwapKitCardanoSignerError.missingFee }
        guard signedFee <= maxFeeLovelace else {
            throw SwapKitCardanoSignerError.feeExceedsCeiling(signedFee)
        }
    }

    private static func verifyOutputs(
        data: Data,
        offset: inout Int,
        vaultAddress: Data,
        fromAmount: BigInt
    ) throws {
        let countArgument = try readArraySize(data: data, offset: &offset)
        guard let count = Int(exactly: countArgument) else {
            throw SwapKitCardanoSignerError.malformedEnvelope("outputs array size is too large")
        }

        var externalOutputs = 0
        for _ in 0..<count {
            let output = try readOutput(data: data, offset: &offset)
            guard output.address != vaultAddress else { continue }

            externalOutputs += 1
            guard externalOutputs <= 1 else {
                throw SwapKitCardanoSignerError.tooManyExternalOutputs
            }
            guard !output.hasAssets, !output.hasExtras else {
                throw SwapKitCardanoSignerError.depositNotPlainADA
            }
            guard BigInt(output.lovelace) <= fromAmount else {
                throw SwapKitCardanoSignerError.depositExceedsQuote(lovelace: output.lovelace)
            }
        }
    }

    private struct CardanoOutput {
        let address: Data
        let lovelace: UInt64
        let hasAssets: Bool
        let hasExtras: Bool
    }

    /// Legacy `[address, value, datum_hash?]` or post-Alonzo
    /// `{0: address, 1: value, 2: datum_option, 3: script_ref}`.
    private static func readOutput(data: Data, offset: inout Int) throws -> CardanoOutput {
        let majorType = try peekMajorType(data: data, offset: &offset)
        switch majorType {
        case cborMajorArray:
            let sizeArgument = try readArraySize(data: data, offset: &offset)
            guard let size = Int(exactly: sizeArgument), size >= 2 else {
                throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output is truncated")
            }
            let address = try readBytes(data: data, offset: &offset)
            let value = try readOutputValue(data: data, offset: &offset)
            var hasExtras = false
            for _ in 0..<(size - 2) {
                hasExtras = true
                offset += try cborItemLength(data: data, offset: offset)
            }
            return CardanoOutput(address: address, lovelace: value.lovelace, hasAssets: value.hasAssets, hasExtras: hasExtras)
        case cborMajorMap:
            let sizeArgument = try readMapSize(data: data, offset: &offset)
            guard let size = Int(exactly: sizeArgument) else {
                throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output map size is too large")
            }
            var address: Data?
            var value: (lovelace: UInt64, hasAssets: Bool)?
            var hasExtras = false
            for _ in 0..<size {
                let key = try readUInt(data: data, offset: &offset)
                switch key {
                case outputAddressKey:
                    address = try readBytes(data: data, offset: &offset)
                case outputValueKey:
                    value = try readOutputValue(data: data, offset: &offset)
                default:
                    hasExtras = true
                    offset += try cborItemLength(data: data, offset: offset)
                }
            }
            guard let address else {
                throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output has no address")
            }
            guard let value else {
                throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output has no value")
            }
            return CardanoOutput(address: address, lovelace: value.lovelace, hasAssets: value.hasAssets, hasExtras: hasExtras)
        default:
            throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output is not an array or map")
        }
    }

    /// `coin` or `[coin, multiasset]`; returns lovelace and whether native
    /// tokens are attached.
    private static func readOutputValue(data: Data, offset: inout Int) throws -> (lovelace: UInt64, hasAssets: Bool) {
        let majorType = try peekMajorType(data: data, offset: &offset)
        if majorType == cborMajorUInt {
            return (try readUInt(data: data, offset: &offset), false)
        }
        let sizeArgument = try readArraySize(data: data, offset: &offset)
        guard sizeArgument == 2 else {
            throw SwapKitCardanoSignerError.malformedEnvelope("Cardano output value is malformed")
        }
        let lovelace = try readUInt(data: data, offset: &offset)
        offset += try cborItemLength(data: data, offset: offset) // skip multiasset
        return (lovelace, true)
    }

    /// `0x61 ‖ blake2b-224(vkey)`, the mainnet Cardano enterprise address
    /// Vultisig derives (see `CoinFactory.createCardanoEnterpriseAddress`,
    /// which returns the same bytes bech32-encoded).
    private static func vaultEnterpriseAddress(publicKey: Data) throws -> Data {
        guard publicKey.count == CardanoSignedTxBuilder.publicKeyLength else {
            throw SwapKitCardanoSignerError.invalidPublicKey(publicKey.hexString)
        }
        let hash = Hash.blake2b(data: publicKey, size: 28)
        return Data([enterpriseMainnetHeader]) + hash
    }

    // MARK: - Body-verification CBOR value decoding
    //
    // Separate from the envelope-level `cborItemLength`/`readBE` walker
    // above (which only needs byte *lengths*): these readers decode actual
    // values (map/array sizes, uints, byte strings) so `verifyBody` can
    // inspect the body's contents. Kept as standalone helpers rather than
    // folded into `cborItemLength` so that function — already pinned by
    // exact byte-count assertions in the envelope tests — stays untouched.

    private static let cborMajorUInt: UInt8 = 0
    private static let cborMajorBytes: UInt8 = 2
    private static let cborMajorArray: UInt8 = 4
    private static let cborMajorMap: UInt8 = 5

    /// A leading tag(258) "set" header (`d9 01 02`), which Conway-era CDDL
    /// wraps some collections in. Nothing here cares about the tag itself,
    /// so every read transparently unwraps it first — same as Android's
    /// `CborReader.skipSetTag`.
    private static func skipSetTag(data: Data, offset: inout Int) {
        let setTagHead: UInt8 = 0xD9
        guard offset + 3 <= data.count,
              data[data.startIndex + offset] == setTagHead,
              data[data.startIndex + offset + 1] == 0x01,
              data[data.startIndex + offset + 2] == 0x02 else { return }
        offset += 3
    }

    /// Major type at `offset`, after unwrapping a leading set tag. Doesn't
    /// consume the item itself — used to branch between shapes (legacy
    /// array vs post-Alonzo map output, uint vs array value) before
    /// committing to a specific reader.
    private static func peekMajorType(data: Data, offset: inout Int) throws -> UInt8 {
        skipSetTag(data: data, offset: &offset)
        guard offset < data.count else { throw SwapKitCardanoSignerError.truncated }
        return data[data.startIndex + offset] >> 5
    }

    private static func readCBORHead(data: Data, offset: inout Int) throws -> (majorType: UInt8, argument: UInt64) {
        skipSetTag(data: data, offset: &offset)
        guard offset < data.count else { throw SwapKitCardanoSignerError.truncated }
        let head = data[data.startIndex + offset]
        offset += 1
        let majorType = head >> 5
        let additionalInfo = head & 0x1f

        let argument: UInt64
        switch additionalInfo {
        case 0...23:
            argument = UInt64(additionalInfo)
        case 24:
            guard offset < data.count else { throw SwapKitCardanoSignerError.truncated }
            argument = UInt64(data[data.startIndex + offset])
            offset += 1
        case 25:
            argument = try readBE(data: data, offset: &offset, bytes: 2)
        case 26:
            argument = try readBE(data: data, offset: &offset, bytes: 4)
        case 27:
            argument = try readBE(data: data, offset: &offset, bytes: 8)
        default:
            throw SwapKitCardanoSignerError.malformedEnvelope(
                "indefinite-length or reserved CBOR additional-info: \(additionalInfo)"
            )
        }
        return (majorType, argument)
    }

    private static func readUInt(data: Data, offset: inout Int) throws -> UInt64 {
        let (majorType, argument) = try readCBORHead(data: data, offset: &offset)
        guard majorType == cborMajorUInt else {
            throw SwapKitCardanoSignerError.malformedEnvelope("expected CBOR uint, got major type \(majorType)")
        }
        return argument
    }

    private static func readBytes(data: Data, offset: inout Int) throws -> Data {
        let (majorType, argument) = try readCBORHead(data: data, offset: &offset)
        guard majorType == cborMajorBytes else {
            throw SwapKitCardanoSignerError.malformedEnvelope("expected CBOR byte string, got major type \(majorType)")
        }
        guard let length = Int(exactly: argument), offset + length <= data.count else {
            throw SwapKitCardanoSignerError.truncated
        }
        let bytes = data[(data.startIndex + offset)..<(data.startIndex + offset + length)]
        offset += length
        return Data(bytes)
    }

    private static func readArraySize(data: Data, offset: inout Int) throws -> UInt64 {
        let (majorType, argument) = try readCBORHead(data: data, offset: &offset)
        guard majorType == cborMajorArray else {
            throw SwapKitCardanoSignerError.malformedEnvelope("expected CBOR array, got major type \(majorType)")
        }
        return argument
    }

    private static func readMapSize(data: Data, offset: inout Int) throws -> UInt64 {
        let (majorType, argument) = try readCBORHead(data: data, offset: &offset)
        guard majorType == cborMajorMap else {
            throw SwapKitCardanoSignerError.malformedEnvelope("expected CBOR map, got major type \(majorType)")
        }
        return argument
    }

    // MARK: - Body-verification constants

    private static let bodyOutputsKey: UInt64 = 1
    private static let bodyFeeKey: UInt64 = 2
    private static let outputAddressKey: UInt64 = 0
    private static let outputValueKey: UInt64 = 1

    /// Body fields a plain payment may carry: inputs (0), ttl (3),
    /// auxiliary-data hash (7), validity start (8) and network id (15).
    /// Outputs (1) and fee (2) are checked separately.
    private static let passiveBodyKeys: Set<UInt64> = [0, 3, 7, 8, 15]

    /// A plain Cardano payment's fee is `a + b·size`. At mainnet's current
    /// parameters (0.155381 ADA + 44 lovelace/byte) even a maximum-size
    /// 16 KiB transaction costs about 0.88 ADA.
    fileprivate static let maxFeeLovelace: UInt64 = 2_000_000

    private static let enterpriseMainnetHeader: UInt8 = 0x61

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
