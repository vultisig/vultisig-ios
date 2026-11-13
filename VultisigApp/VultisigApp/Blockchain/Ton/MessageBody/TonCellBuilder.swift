//
//  TonCellBuilder.swift
//  VultisigApp
//

import BigInt
import Foundation

enum TonCellBuilderError: Error, Equatable {
    case cellOverflow
    case tooManyRefs
    case valueTooLarge
    case invalidAddress
}

/// An ordinary cell produced by `TonCellBuilder`, the write-side twin of the decoder's `TonCell`.
struct TonBuiltCell: Equatable {
    let data: [UInt8]
    let bitLength: Int
    let refs: [TonBuiltCell]
}

/// Builds one ordinary TON cell, mirroring `@ton/core`'s `Builder` for the fields the app writes
/// itself (Tonstakers deposit, tsTON burn). Matches Android's `TonCellBuilder` bit for bit.
final class TonCellBuilder {
    private static let maxBits = 1023
    private static let maxRefs = 4

    private var data = [UInt8](repeating: 0, count: maxBits / 8 + 1)
    private var bitLength = 0
    private var refs: [TonBuiltCell] = []

    init() {}

    @discardableResult
    func storeBit(_ value: Bool) throws -> TonCellBuilder {
        guard bitLength < Self.maxBits else { throw TonCellBuilderError.cellOverflow }
        if value {
            data[bitLength / 8] |= UInt8(1 << (7 - bitLength % 8))
        }
        bitLength += 1
        return self
    }

    /// Stores `value` in `bits` (≤ 64) bits, most-significant first.
    @discardableResult
    func storeUInt(_ value: UInt64, bits: Int) throws -> TonCellBuilder {
        guard bits >= 0, bits <= 64 else { throw TonCellBuilderError.valueTooLarge }
        if bits < 64, value >> UInt64(bits) != 0 { throw TonCellBuilderError.valueTooLarge }
        guard bits > 0 else { return self }
        for index in stride(from: bits - 1, through: 0, by: -1) {
            try storeBit((value >> UInt64(index)) & 1 == 1)
        }
        return self
    }

    @discardableResult
    func storeUIntBig(_ value: BigUInt, bits: Int) throws -> TonCellBuilder {
        guard value.bitWidth <= bits else { throw TonCellBuilderError.valueTooLarge }
        guard bits > 0 else { return self }
        for index in stride(from: bits - 1, through: 0, by: -1) {
            try storeBit(value[bitAt: index])
        }
        return self
    }

    /// `VarUInteger 16` coins: minimal byte length in a nibble, then the value in that many bytes.
    @discardableResult
    func storeCoins(_ value: BigInt) throws -> TonCellBuilder {
        guard value.sign == .plus else { throw TonCellBuilderError.valueTooLarge }
        let magnitude = value.magnitude
        let byteCount = (magnitude.bitWidth + 7) / 8
        guard byteCount <= 15 else { throw TonCellBuilderError.valueTooLarge }
        try storeUInt(UInt64(byteCount), bits: 4)
        return try storeUIntBig(magnitude, bits: byteCount * 8)
    }

    /// `addr_std$10`, no anycast. Takes the raw `workchain:hex` form.
    @discardableResult
    func storeAddress(raw: String) throws -> TonCellBuilder {
        guard let separator = raw.firstIndex(of: ":"),
              let workchain = Int(raw[raw.startIndex..<separator]),
              (-128...127).contains(workchain) else {
            throw TonCellBuilderError.invalidAddress
        }
        let hash = String(raw[raw.index(after: separator)...])
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit),
              let hashValue = BigUInt(hash, radix: 16) else {
            throw TonCellBuilderError.invalidAddress
        }
        try storeUInt(0b10, bits: 2)
        try storeBit(false)
        try storeUInt(UInt64(UInt8(bitPattern: Int8(workchain))), bits: 8)
        return try storeUIntBig(hashValue, bits: 256)
    }

    @discardableResult
    func storeRef(_ cell: TonBuiltCell) throws -> TonCellBuilder {
        guard refs.count < Self.maxRefs else { throw TonCellBuilderError.tooManyRefs }
        refs.append(cell)
        return self
    }

    /// `Maybe ^Cell`: a set bit then the ref, or a clear bit alone.
    @discardableResult
    func storeMaybeRef(_ cell: TonBuiltCell?) throws -> TonCellBuilder {
        try storeBit(cell != nil)
        if let cell { try storeRef(cell) }
        return self
    }

    func build() -> TonBuiltCell {
        TonBuiltCell(data: Array(data.prefix((bitLength + 7) / 8)), bitLength: bitLength, refs: refs)
    }
}

/// Serializes a cell tree into a single-root BOC laid out like `@ton/core`'s default
/// `Cell.toBoc()`: no index, CRC-32C trailer, cells in depth-first pre-order.
enum TonBocSerializer {
    static func toBase64(_ root: TonBuiltCell, withCrc32c: Bool = true) -> String {
        Data(serialize(root, withCrc32c: withCrc32c)).base64EncodedString()
    }

    static func serialize(_ root: TonBuiltCell, withCrc32c: Bool = true) -> [UInt8] {
        var cells: [(cell: TonBuiltCell, refIndices: [Int])] = []
        _ = collect(root, into: &cells)

        let sizeBytes = bytesNeeded(UInt64(cells.count))
        let serialized = cells.map { serializeCell($0.cell, refIndices: $0.refIndices, sizeBytes: sizeBytes) }
        let totalSize = serialized.reduce(0) { $0 + $1.count }
        let offBytes = bytesNeeded(UInt64(totalSize))

        var out: [UInt8] = [0xb5, 0xee, 0x9c, 0x72]
        out.append((withCrc32c ? 0x40 : 0x00) | UInt8(sizeBytes))
        out.append(UInt8(offBytes))
        out += bigEndian(UInt64(cells.count), sizeBytes)
        out += bigEndian(1, sizeBytes)
        out += bigEndian(0, sizeBytes)
        out += bigEndian(UInt64(totalSize), offBytes)
        out += bigEndian(0, sizeBytes)
        serialized.forEach { out += $0 }

        guard withCrc32c else { return out }
        let crc = crc32c(out)
        out += [UInt8(crc & 0xff), UInt8((crc >> 8) & 0xff), UInt8((crc >> 16) & 0xff), UInt8((crc >> 24) & 0xff)]
        return out
    }

    /// Pre-order: a parent takes its index before its refs, so every ref points forward.
    private static func collect(_ cell: TonBuiltCell, into cells: inout [(cell: TonBuiltCell, refIndices: [Int])]) -> Int {
        let index = cells.count
        cells.append((cell, []))
        let refIndices = cell.refs.map { collect($0, into: &cells) }
        cells[index].refIndices = refIndices
        return index
    }

    private static func serializeCell(_ cell: TonBuiltCell, refIndices: [Int], sizeBytes: Int) -> [UInt8] {
        let fullBytes = cell.bitLength / 8
        let hasPartial = cell.bitLength % 8 != 0
        let dataBytes = fullBytes + (hasPartial ? 1 : 0)

        var out: [UInt8] = [UInt8(cell.refs.count), UInt8(fullBytes + dataBytes)]
        var data = Array(cell.data.prefix(dataBytes))
        if data.count < dataBytes { data += [UInt8](repeating: 0, count: dataBytes - data.count) }
        if hasPartial {
            data[fullBytes] |= UInt8(1 << (7 - cell.bitLength % 8))
        }
        out += data
        refIndices.forEach { out += bigEndian(UInt64($0), sizeBytes) }
        return out
    }

    private static func bytesNeeded(_ value: UInt64) -> Int {
        var bytes = 1
        var remaining = value >> 8
        while remaining != 0 {
            bytes += 1
            remaining >>= 8
        }
        return bytes
    }

    private static func bigEndian(_ value: UInt64, _ byteCount: Int) -> [UInt8] {
        (0..<byteCount).reversed().map { UInt8((value >> (8 * UInt64($0))) & 0xff) }
    }

    private static func crc32c(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x82F63B78 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// Converts a mainnet user-friendly TON address (base64 or base64url) to raw `workchain:hex`; raw
/// input is normalized and returned. `nil` for a bad tag, a testnet address or a CRC mismatch, so a
/// typo fails closed instead of becoming another account.
func tonFriendlyToRaw(_ address: String) -> String? {
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    if let separator = trimmed.firstIndex(of: ":") {
        guard let workchain = Int(trimmed[trimmed.startIndex..<separator]) else { return nil }
        let hash = trimmed[trimmed.index(after: separator)...].lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return "\(workchain):\(hash)"
    }
    guard trimmed.count == 48 else { return nil }
    let standard = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    guard let bytes = Data(base64Encoded: standard), bytes.count == 36 else { return nil }
    // 0x11 bounceable, 0x51 non-bounceable; the 0x80 testnet bit is rejected.
    guard bytes[0] == 0x11 || bytes[0] == 0x51 else { return nil }
    let checksum = UInt16(bytes[34]) << 8 | UInt16(bytes[35])
    guard tonAddressCrc16(Array(bytes[0..<34])) == checksum else { return nil }
    let workchain = Int(Int8(bitPattern: bytes[1]))
    let hash = bytes[2..<34].map { String(format: "%02x", $0) }.joined()
    return "\(workchain):\(hash)"
}

/// CRC16-XMODEM, the checksum TON appends to user-friendly addresses.
private func tonAddressCrc16(_ bytes: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0
    for byte in bytes {
        crc ^= UInt16(byte) << 8
        for _ in 0..<8 {
            crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
        }
    }
    return crc
}
