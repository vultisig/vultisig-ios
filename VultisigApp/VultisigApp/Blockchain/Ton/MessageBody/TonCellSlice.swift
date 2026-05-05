//
//  TonCellSlice.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-cell-slice")

/// Errors thrown by the minimal TON BOC parser. They are intentionally caught
/// at decoder boundaries so a malformed/truncated body falls back to "unknown"
/// rather than crashing the keysign UI.
enum TonCellError: Error {
    case invalidMagic
    case truncatedBoc
    case invalidCellHeader
    case missingRef
    case missingBits
    case unsupportedCellType
    case invalidAddress
    case invalidCoinsLength
    case invalidNumber
}

/// Magic bytes that identify a TON BOC. Only `b5ee9c72` is used by the
/// reference `@ton/core` serializer, but historical/alternate magics are
/// accepted by some implementations and we surface them so hex→base64
/// detection matches the SDK exactly.
enum TonBocMagic {
    static let prefixes: [String] = ["b5ee9c72", "68ff65f3", "acc3a728"]
}

/// Immutable cell parsed from a BOC. Only the data needed for body decode is
/// retained: the bit payload, the ordered refs, and the exotic flag (which we
/// always reject — Vultisig only signs ordinary cells).
struct TonCell {
    let bits: TonBitString
    let refs: [TonCell]

    /// Begin reading this cell as a slice. The slice owns its own cursor
    /// state so the underlying cell can be re-parsed if needed.
    func beginParse() -> TonSlice {
        TonSlice(bits: bits, refs: refs)
    }
}

/// A bit-addressable byte buffer. Length is tracked in bits because TON cells
/// carry a non-byte-aligned bit count.
struct TonBitString {
    let bytes: [UInt8]
    let length: Int // bit length

    func bit(at index: Int) -> Bool {
        guard index >= 0, index < length else { return false }
        let byte = bytes[index / 8]
        let mask: UInt8 = 1 << (7 - (index % 8))
        return (byte & mask) != 0
    }
}

/// Cursor over a `TonBitString` and its refs. Mirrors `@ton/core`'s `Slice`
/// just enough to decode the message-body shapes Vultisig surfaces.
final class TonSlice {
    private let bits: TonBitString
    private var refs: [TonCell]
    private var bitOffset: Int = 0

    init(bits: TonBitString, refs: [TonCell]) {
        self.bits = bits
        self.refs = refs
    }

    var remainingBits: Int { bits.length - bitOffset }
    var remainingRefs: Int { refs.count }

    func loadBit() throws -> Bool {
        guard remainingBits >= 1 else { throw TonCellError.missingBits }
        let value = bits.bit(at: bitOffset)
        bitOffset += 1
        return value
    }

    /// Load `count` bits as an unsigned integer. `count` must be ≤ 64 because
    /// the message-body shapes we decode never read more than 64 bits at once
    /// outside `loadCoins` (which uses `loadUInt128` internally).
    func loadUInt(bits count: Int) throws -> UInt64 {
        guard count >= 0, count <= 64 else { throw TonCellError.invalidNumber }
        guard remainingBits >= count else { throw TonCellError.missingBits }
        var value: UInt64 = 0
        for _ in 0..<count {
            value <<= 1
            if bits.bit(at: bitOffset) { value |= 1 }
            bitOffset += 1
        }
        return value
    }

    /// Load `count` bits into a big-endian byte array. Used by `loadCoins`
    /// when the value width exceeds 64 bits.
    func loadBigUInt(bits count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw TonCellError.invalidNumber }
        guard remainingBits >= count else { throw TonCellError.missingBits }
        let byteCount = (count + 7) / 8
        var out = [UInt8](repeating: 0, count: byteCount)
        let leadingZero = (8 - (count % 8)) % 8
        var pos = 0
        for _ in 0..<count {
            let bit: UInt8 = bits.bit(at: bitOffset) ? 1 : 0
            let absolutePos = pos + leadingZero
            out[absolutePos / 8] |= bit << (7 - (absolutePos % 8))
            bitOffset += 1
            pos += 1
        }
        return out
    }

    /// `var_uint$_ len:(## 4) value:(uint (len * 8))` — TON's variable-length
    /// "Coins" / Grams encoding. Returned as a decimal string because amounts
    /// can exceed UInt64 (jetton supplies are 256-bit) and BigInt isn't
    /// available in this module without dragging the BigInt SPM in.
    func loadCoins() throws -> String {
        let length = try loadUInt(bits: 4)
        if length == 0 { return "0" }
        let bitCount = Int(length) * 8
        guard bitCount <= 256 else { throw TonCellError.invalidCoinsLength }
        let bytes = try loadBigUInt(bits: bitCount)
        return decimalString(fromBigEndian: bytes)
    }

    func loadRef() throws -> TonCell {
        guard !refs.isEmpty else { throw TonCellError.missingRef }
        return refs.removeFirst()
    }

    /// Drain remaining bits + refs into a freshly-built cell, preserving the
    /// bit ordering. Used when `forward_payload` is encoded inline (`Either
    /// Cell` discriminator = 0) — the tail of the parent slice IS the payload
    /// and must be re-parsed from offset zero.
    func asRemainingCell() -> TonCell {
        let remaining = bits.length - bitOffset
        var bytes = [UInt8](repeating: 0, count: (remaining + 7) / 8)
        for index in 0..<remaining {
            if bits.bit(at: bitOffset + index) {
                bytes[index / 8] |= 1 << (7 - (index % 8))
            }
        }
        let drainedRefs = refs
        bitOffset = bits.length
        refs = []
        return TonCell(bits: TonBitString(bytes: bytes, length: remaining), refs: drainedRefs)
    }

    /// Skip a `Maybe ^Cell` field. Returns the ref when the discriminator bit
    /// is set; throws if the discriminator is set but no ref is available.
    func loadMaybeRef() throws -> TonCell? {
        let hasRef = try loadBit()
        guard hasRef else { return nil }
        return try loadRef()
    }

    /// Read a TLB `MsgAddressInt`. Returns the user-friendly bounceable form
    /// produced by WalletCore so it round-trips with the rest of the app.
    /// Throws on `addr_none` — callers that want optional behaviour use
    /// `loadMaybeAddress`.
    func loadAddress() throws -> String {
        guard let address = try loadAddressInternal(allowNone: false) else {
            throw TonCellError.invalidAddress
        }
        return address
    }

    /// Read an optional `MsgAddress`. Returns nil for `addr_none$00`, throws on
    /// any malformed encoding.
    func loadMaybeAddress() throws -> String? {
        try loadAddressInternal(allowNone: true)
    }

    private func loadAddressInternal(allowNone: Bool) throws -> String? {
        guard remainingBits >= 2 else { throw TonCellError.invalidAddress }
        let kind = try loadUInt(bits: 2)
        switch kind {
        case 0b00:
            if allowNone { return nil }
            throw TonCellError.invalidAddress
        case 0b10:
            // anycast: (Maybe Anycast)
            let hasAnycast = try loadBit()
            if hasAnycast {
                // depth:(#<= 30) rewrite_pfx:bits depth — not exercised by
                // jetton/nft/swap bodies; skip with a defensive throw rather
                // than guess at the encoding.
                throw TonCellError.invalidAddress
            }
            let workchainRaw = try loadUInt(bits: 8)
            // workchain is signed int8: reinterpret high-bit as sign.
            let workchain = Int8(bitPattern: UInt8(truncatingIfNeeded: workchainRaw))
            let hashBytes = try loadBigUInt(bits: 256)
            let hex = hashBytes.map { String(format: "%02x", $0) }.joined()
            let raw = "\(workchain):\(hex)"
            // WalletCore returns nil when the raw form is invalid; in that
            // case we surface the raw form so the caller still sees a
            // diagnosable string instead of a parse failure.
            return TONAddressConverter.toUserFriendly(address: raw, bounceable: true, testnet: false) ?? raw
        default:
            // var_addr / extern unsupported in keysign-message bodies.
            throw TonCellError.invalidAddress
        }
    }
}

/// Top-level BOC parser. Converts the base64 (or hex) BOC payload to the root
/// cell of its tree. Only the root cell + its descendant refs are reachable —
/// indexed/exotic BOCs are rejected because no Vultisig-emitted body uses them.
enum TonBocParser {

    /// Convert hex-encoded BOC to base64 when one of the recognised magic
    /// prefixes is present. Mirrors `tonPayloadToBase64` in the SDK so hex
    /// payloads coming from dApps still reach the decoder.
    static func payloadToBase64(_ payload: String?) -> String? {
        guard let payload, !payload.isEmpty else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isHexBoc(trimmed), let data = hexData(trimmed) {
            return data.base64EncodedString()
        }
        return trimmed
    }

    static func parse(base64: String) throws -> TonCell {
        guard let data = Data(base64Encoded: base64) else {
            throw TonCellError.truncatedBoc
        }
        return try parse(bytes: [UInt8](data))
    }

    private static func parse(bytes: [UInt8]) throws -> TonCell {
        guard bytes.count >= 6 else { throw TonCellError.truncatedBoc }
        // Only the canonical b5ee9c72 magic carries a parseable BOC layout —
        // the alternate magics surface in `payloadToBase64` for hex
        // detection but never appear in payloads we actually decode.
        guard bytes[0] == 0xb5, bytes[1] == 0xee, bytes[2] == 0x9c, bytes[3] == 0x72 else {
            throw TonCellError.invalidMagic
        }

        var cursor = 4
        let flagsByte = bytes[cursor]; cursor += 1
        let hasIdx = (flagsByte & 0x80) != 0
        let hasCrc32c = (flagsByte & 0x40) != 0
        let hasCacheBits = (flagsByte & 0x20) != 0
        // bits 4..3 are TLB-defined flags we don't use.
        let sizeBytes = Int(flagsByte & 0x07)
        guard sizeBytes >= 1, sizeBytes <= 4 else { throw TonCellError.truncatedBoc }
        // hasCacheBits is just metadata for cell caching; ignore.
        _ = hasCacheBits

        guard cursor < bytes.count else { throw TonCellError.truncatedBoc }
        let offBytes = Int(bytes[cursor]); cursor += 1
        guard offBytes >= 1, offBytes <= 8 else { throw TonCellError.truncatedBoc }

        guard cursor + sizeBytes * 3 + offBytes <= bytes.count else {
            throw TonCellError.truncatedBoc
        }
        // sizeBytes ≤ 4 → reads are ≤ 32 bits → always fit in Int on 64-bit
        // platforms. `totCellsSize` reads up to 8 bytes (offBytes ≤ 8), so a
        // hostile header could declare a value beyond Int.max — use the
        // failable `Int(exactly:)` to surface that as a parse error rather
        // than a `Int(_:)` trap.
        let cellsCount = Int(readBigEndian(bytes: bytes, offset: cursor, length: sizeBytes))
        cursor += sizeBytes
        let rootsCount = Int(readBigEndian(bytes: bytes, offset: cursor, length: sizeBytes))
        cursor += sizeBytes
        let absentCount = Int(readBigEndian(bytes: bytes, offset: cursor, length: sizeBytes))
        cursor += sizeBytes
        let totCellsSizeRaw = readBigEndian(bytes: bytes, offset: cursor, length: offBytes)
        guard let totCellsSize = Int(exactly: totCellsSizeRaw) else {
            throw TonCellError.truncatedBoc
        }
        cursor += offBytes

        // Single-root BOCs only — the parser returns one `TonCell`, so
        // accepting `rootsCount > 1` would silently drop siblings and let an
        // attacker hide payload outside the Verify summary's view.
        guard rootsCount == 1, absentCount == 0, cellsCount >= rootsCount else {
            throw TonCellError.truncatedBoc
        }

        // root_list
        let rootListSize = rootsCount * sizeBytes
        guard cursor + rootListSize <= bytes.count else { throw TonCellError.truncatedBoc }
        let rootIndex = Int(readBigEndian(bytes: bytes, offset: cursor, length: sizeBytes))
        cursor += rootListSize
        guard rootIndex < cellsCount else { throw TonCellError.truncatedBoc }

        if hasIdx {
            // index: cellsCount * offBytes
            let indexSize = cellsCount * offBytes
            guard cursor + indexSize <= bytes.count else { throw TonCellError.truncatedBoc }
            cursor += indexSize
        }

        // Strict envelope: the buffer must end exactly at the cells data plus
        // the optional 4-byte CRC trailer. Trailing junk would otherwise let
        // an attacker hide bytes outside the parser's view.
        let trailerSize = hasCrc32c ? 4 : 0
        guard cursor + totCellsSize + trailerSize == bytes.count else {
            throw TonCellError.truncatedBoc
        }

        // Each serialized cell needs at least its 2-byte d1+d2 header, so
        // `cellsCount` is bounded by `totCellsSize / 2`. Without this guard
        // a malformed header could request an extreme cell count and exhaust
        // memory before the structural failure surfaces.
        guard cellsCount <= totCellsSize / 2 else {
            throw TonCellError.invalidCellHeader
        }

        // Phase 1: parse each cell into raw form (bits + ref indices).
        struct RawCell {
            let bits: TonBitString
            let refIndices: [Int]
        }
        var rawCells: [RawCell] = []
        rawCells.reserveCapacity(cellsCount)

        var cellsCursor = cursor
        for _ in 0..<cellsCount {
            guard cellsCursor + 2 <= cursor + totCellsSize else { throw TonCellError.invalidCellHeader }
            let d1 = bytes[cellsCursor]; cellsCursor += 1
            let d2 = bytes[cellsCursor]; cellsCursor += 1
            let refsCount = Int(d1 & 0x07)
            let isExotic = (d1 & 0x08) != 0
            // hasHashes (d1 & 0x10) only adds extra bytes we don't read.
            let hasHashes = (d1 & 0x10) != 0
            // d1 high bits beyond 0x1f are level mask; not used for decode.
            if isExotic { throw TonCellError.unsupportedCellType }

            let dataBytes = (Int(d2) + 1) / 2
            let isAligned = (d2 & 1) == 0

            if hasHashes {
                // Skip pruned-branch hashes if present: 32 bytes per hash + 2 bytes per depth
                // for each level. We don't use them but must skip to remain in sync.
                // Level mask = (d1 >> 5) & 7; level count = popcount(mask) + 1, but
                // for ordinary cells level is 0 → 1 hash + 1 depth.
                let levelMask = Int((d1 >> 5) & 0x07)
                let levels = levelMask.nonzeroBitCount + 1
                let skip = levels * (32 + 2)
                guard cellsCursor + skip <= cursor + totCellsSize else { throw TonCellError.invalidCellHeader }
                cellsCursor += skip
            }

            guard cellsCursor + dataBytes <= cursor + totCellsSize else { throw TonCellError.invalidCellHeader }
            let payload = Array(bytes[cellsCursor..<(cellsCursor + dataBytes)])
            cellsCursor += dataBytes

            let bitLen: Int
            if isAligned {
                bitLen = dataBytes * 8
            } else {
                // Non-aligned (odd d2) cells append a `1` bit then `0`s up
                // to the next byte boundary. The marker is the lowest set
                // bit in the trailing byte; everything at or below it is
                // padding and must be stripped to recover the real bit
                // length. A trailing byte of all zeros means no marker —
                // the cell is malformed.
                guard let last = payload.last, last != 0 else {
                    throw TonCellError.invalidCellHeader
                }
                let trailing = last.trailingZeroBitCount + 1
                bitLen = dataBytes * 8 - trailing
            }
            let bits = TonBitString(bytes: payload, length: bitLen)

            guard cellsCursor + refsCount * sizeBytes <= cursor + totCellsSize else {
                throw TonCellError.invalidCellHeader
            }
            var refIndices: [Int] = []
            refIndices.reserveCapacity(refsCount)
            for _ in 0..<refsCount {
                let idx = Int(readBigEndian(bytes: bytes, offset: cellsCursor, length: sizeBytes))
                cellsCursor += sizeBytes
                guard idx < cellsCount else { throw TonCellError.invalidCellHeader }
                refIndices.append(idx)
            }
            rawCells.append(RawCell(bits: bits, refIndices: refIndices))
        }

        // Cells must consume the declared region exactly — any leftover bytes
        // mean the header lies about `totCellsSize`.
        guard cellsCursor == cursor + totCellsSize else {
            throw TonCellError.invalidCellHeader
        }

        // Phase 2: tie refs together. BOCs serialize children before parents,
        // so iterating from the last cell upward guarantees referenced cells
        // already exist.
        var resolved: [TonCell?] = Array(repeating: nil, count: cellsCount)
        for index in stride(from: cellsCount - 1, through: 0, by: -1) {
            let raw = rawCells[index]
            let children: [TonCell] = try raw.refIndices.map { childIndex in
                guard let child = resolved[childIndex] else { throw TonCellError.invalidCellHeader }
                return child
            }
            resolved[index] = TonCell(bits: raw.bits, refs: children)
        }

        guard let root = resolved[rootIndex] else { throw TonCellError.truncatedBoc }
        if hasCrc32c {
            // CRC32C trailer (Castagnoli) covers every byte before the 4-byte
            // checksum, stored little-endian per `@ton/core`'s deserializer.
            // Anchor `crcStart` to the declared cells boundary (not buffer
            // end) so the strict envelope check earlier in this function is
            // the single source of truth for total length.
            let crcStart = cursor + totCellsSize
            let stored = UInt32(bytes[crcStart])
                | (UInt32(bytes[crcStart + 1]) << 8)
                | (UInt32(bytes[crcStart + 2]) << 16)
                | (UInt32(bytes[crcStart + 3]) << 24)
            let computed = crc32c(Array(bytes[..<crcStart]))
            guard stored == computed else { throw TonCellError.invalidCellHeader }
        }
        return root
    }

    /// CRC-32C (Castagnoli) — polynomial `0x1EDC6F41`, reflected `0x82F63B78`.
    /// Standard `init = final XOR = 0xFFFFFFFF`. Used to validate the BOC
    /// trailer when the header sets `hasCrc32c`.
    private static func crc32c(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) != 0 ? 0x82F63B78 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func isHexBoc(_ payload: String) -> Bool {
        guard !payload.isEmpty, payload.count % 2 == 0 else { return false }
        let allowed = Set("0123456789abcdefABCDEF")
        guard payload.unicodeScalars.allSatisfy({ allowed.contains(Character($0)) }) else {
            return false
        }
        let lower = payload.lowercased()
        return TonBocMagic.prefixes.contains(where: { lower.hasPrefix($0) })
    }

    private static func hexData(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var byte: UInt8 = 0
        var nibble = 0
        for scalar in hex.unicodeScalars {
            let value: UInt8
            switch scalar {
            case "0"..."9": value = UInt8(scalar.value - 0x30)
            case "a"..."f": value = UInt8(scalar.value - 0x57)
            case "A"..."F": value = UInt8(scalar.value - 0x37)
            default: return nil
            }
            if nibble == 0 {
                byte = value << 4
                nibble = 1
            } else {
                byte |= value
                data.append(byte)
                nibble = 0
            }
        }
        return nibble == 0 ? data : nil
    }

    private static func readBigEndian(bytes: [UInt8], offset: Int, length: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<length {
            result = (result << 8) | UInt64(bytes[offset + index])
        }
        return result
    }

}

/// Convert a big-endian unsigned byte array to a base-10 string. Accepts up
/// to 256-bit values — sufficient for jetton coin amounts.
func decimalString(fromBigEndian bytes: [UInt8]) -> String {
    if bytes.allSatisfy({ $0 == 0 }) { return "0" }
    // Multiply-and-add over a base-10^9 buffer: for each input byte we shift
    // the accumulator left 8 bits and add the byte, propagating carries
    // through the digit array. Allocation-light and avoids pulling BigInt
    // into this module just for a 1–256 bit conversion.
    var digits: [UInt32] = []
    for byte in bytes {
        var carry: UInt64 = UInt64(byte)
        for index in 0..<digits.count {
            let value = UInt64(digits[index]) * 256 + carry
            digits[index] = UInt32(value % 1_000_000_000)
            carry = value / 1_000_000_000
        }
        while carry > 0 {
            digits.append(UInt32(carry % 1_000_000_000))
            carry /= 1_000_000_000
        }
    }
    var result = ""
    for (offset, chunk) in digits.reversed().enumerated() {
        if offset == 0 {
            result += "\(chunk)"
        } else {
            result += String(format: "%09u", chunk)
        }
    }
    return result
}
