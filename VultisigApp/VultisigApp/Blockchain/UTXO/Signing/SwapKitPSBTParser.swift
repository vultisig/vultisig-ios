//
//  SwapKitPSBTParser.swift
//  VultisigApp
//
//  Shared BIP-174 PSBT framing primitives. Every SwapKit UTXO signer (BTC
//  segwit, DOGE / BCH / DASH legacy P2PKH, ZEC Sapling-v4) consumes the same
//  byte-level envelope — magic prefix, global key/value map, per-input map,
//  per-output map. Per-chain signers only diverge on the **unsigned-tx body**
//  parser (which lives in each signer alongside the chain's serialization
//  rules) and on script-type classification.
//
//  Lifted out of `SwapKitBTCSigner` so the new per-chain signers don't
//  duplicate the wire-cursor code. No behaviour change for BTC: the BTC
//  signer's input/output map dictionaries are produced from the same parser
//  output. The BTC unsigned-tx body parser stays in `SwapKitBTCSigner` —
//  it's BIP-144-shaped, distinct from ZEC's Sapling-v4 body.
//

import Foundation

/// Errors surfaced by the shared PSBT framing parser. Per-signer errors wrap
/// these so call sites still see typed `SwapKit<Chain>SignerError` cases.
enum SwapKitPSBTParserError: Error, LocalizedError {
    case missingPSBT
    case truncated
    case invalidMagic

    var errorDescription: String? {
        switch self {
        case .missingPSBT:
            return "SwapKit PSBT payload is empty"
        case .truncated:
            return "SwapKit PSBT is truncated"
        case .invalidMagic:
            return "SwapKit PSBT magic bytes are invalid"
        }
    }
}

/// Decoded PSBT framing — header consumed, globals map parsed, per-input and
/// per-output maps parsed. The unsigned-tx body (the value at global key
/// `0x00`) is exposed as raw bytes; per-chain signers parse the body
/// themselves because the serialization differs (BIP-144 segwit body for
/// BTC, plain legacy body for DOGE/BCH/DASH, Sapling-v4 body for ZEC).
struct ParsedPSBT {
    let globals: [Data: Data]
    /// Raw bytes of the `PSBT_GLOBAL_UNSIGNED_TX` value (global key `0x00`).
    let unsignedTxBytes: Data
    /// One map per input slot in the unsigned tx. Key/value records are
    /// raw bytes — per-chain signers walk them by BIP-174 key types
    /// (`0x00 = NON_WITNESS_UTXO`, `0x01 = WITNESS_UTXO`, `0x03 = SIGHASH`,
    /// `0x04 = REDEEM_SCRIPT`, ...).
    let inputMaps: [[Data: Data]]
    /// One map per output slot in the unsigned tx. Always parsed (forward-
    /// compat / spec compliance) even though current signers don't read
    /// per-output PSBT fields.
    let outputMaps: [[Data: Data]]
}

enum SwapKitPSBTParser {

    /// Parse a PSBT envelope into the framing structure. The caller supplies
    /// `expectedInputCount` and `expectedOutputCount` — derived from the
    /// chain-specific unsigned-tx body parser — so this helper knows how
    /// many input/output maps to read off the cursor.
    static func parse(
        psbtBytes: Data,
        expectedInputCount: Int,
        expectedOutputCount: Int
    ) throws -> ParsedPSBT {
        guard !psbtBytes.isEmpty else { throw SwapKitPSBTParserError.missingPSBT }
        var cursor = PSBTCursor(data: psbtBytes)
        try cursor.expectMagic()
        let globals = try cursor.readMap()
        guard let unsignedTx = globals[Data([0x00])] else {
            // The global `PSBT_GLOBAL_UNSIGNED_TX` is mandatory in BIP-174.
            // Surface as `truncated` (the same error the BTC signer threw
            // before the refactor) rather than introducing a new case — the
            // caller wraps it into the per-chain `missingUnsignedTx`.
            throw SwapKitPSBTParserError.truncated
        }
        var inputMaps: [[Data: Data]] = []
        inputMaps.reserveCapacity(expectedInputCount)
        for _ in 0..<expectedInputCount {
            inputMaps.append(try cursor.readMap())
        }
        var outputMaps: [[Data: Data]] = []
        outputMaps.reserveCapacity(expectedOutputCount)
        for _ in 0..<expectedOutputCount {
            outputMaps.append(try cursor.readMap())
        }
        return ParsedPSBT(
            globals: globals,
            unsignedTxBytes: unsignedTx,
            inputMaps: inputMaps,
            outputMaps: outputMaps
        )
    }

    /// Two-phase variant for signers that don't know the input/output counts
    /// up front — read the header + globals here, then call `readMap()` on
    /// the returned cursor once per input and once per output.
    static func parseFraming(psbtBytes: Data) throws -> (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data) {
        guard !psbtBytes.isEmpty else { throw SwapKitPSBTParserError.missingPSBT }
        var cursor = PSBTCursor(data: psbtBytes)
        try cursor.expectMagic()
        let globals = try cursor.readMap()
        guard let unsignedTx = globals[Data([0x00])] else {
            throw SwapKitPSBTParserError.truncated
        }
        return (cursor, globals, unsignedTx)
    }
}

// MARK: - PSBT byte cursor (BIP-174 wire helpers)

/// Cursor into the PSBT byte stream. Public-ish (`internal` access) so
/// per-chain signers can stream per-input / per-output maps after consuming
/// the framing header. All readers throw `SwapKitPSBTParserError` so the
/// per-chain signer wraps once and presents typed errors.
struct PSBTCursor {
    let data: Data
    var offset: Int = 0

    init(data: Data) { self.data = data }

    var isAtEnd: Bool { offset >= data.count }

    mutating func expectMagic() throws {
        // BIP-174 magic: 4-byte ASCII 'psbt' (0x70 0x73 0x62 0x74) followed
        // by a single separator byte 0xff. Total 5 bytes. After this the
        // global key-value records start — the first byte we read in
        // `readMap()` is the length of the first key (typically 0x01 for
        // PSBT_GLOBAL_UNSIGNED_TX).
        let magic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xff]
        guard data.count >= magic.count else { throw SwapKitPSBTParserError.invalidMagic }
        for i in 0..<magic.count where data[data.startIndex + i] != magic[i] {
            throw SwapKitPSBTParserError.invalidMagic
        }
        offset = magic.count
    }

    mutating func readMap() throws -> [Data: Data] {
        var map: [Data: Data] = [:]
        while true {
            let keyLen = try readCompactSize()
            if keyLen == 0 { return map } // 0x00 terminator
            let key = try readBytes(Int(keyLen))
            let valLen = try readCompactSize()
            let val = try readBytes(Int(valLen))
            map[key] = val
        }
    }

    mutating func readCompactSize() throws -> UInt64 {
        let head = try readByte()
        switch head {
        case 0xff: return try readUInt64LE()
        case 0xfe: return UInt64(try readUInt32LE())
        case 0xfd: return UInt64(try readUInt16LE())
        default: return UInt64(head)
        }
    }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw SwapKitPSBTParserError.truncated }
        let b = data[data.startIndex + offset]
        offset += 1
        return b
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw SwapKitPSBTParserError.truncated
        }
        let start = data.startIndex + offset
        let slice = data[start..<(start + count)]
        offset += count
        return Data(slice)
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let b = try readBytes(2)
        return b.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
    mutating func readUInt32LE() throws -> UInt32 {
        let b = try readBytes(4)
        return b.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
    mutating func readUInt64LE() throws -> UInt64 {
        let b = try readBytes(8)
        return b.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }
    mutating func readInt64LE() throws -> Int64 {
        let unsigned = try readUInt64LE()
        return Int64(bitPattern: unsigned)
    }
}
