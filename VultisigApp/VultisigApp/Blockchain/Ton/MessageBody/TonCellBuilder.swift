//
//  TonCellBuilder.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Errors thrown while building a TON cell / BOC. Kept separate from the
/// decoder's `TonCellError` because the failure modes differ (the builder
/// rejects out-of-range inputs at write time rather than malformed bytes at
/// read time).
enum TonCellBuilderError: Error {
    case negativeValue
    case valueTooLarge
    case invalidAddress
    case cellOverflow
}

/// Minimal single-cell TON BOC encoder — the one net-new crypto primitive the
/// Tonstakers liquid-staking flow needs (WalletCore 4.6.x ships no general cell
/// encoder, only fixed builders for `comment` and the standard jetton transfer).
///
/// Scope is deliberately narrow: it stores the exact TLB fields a jetton-burn
/// body requires (`uint`, `VarUInteger 16` coins, `addr_std$10` `MsgAddress`,
/// and a single maybe-bit), then serialises ONE ordinary root cell with no refs
/// into a canonical BOC (`b5ee9c72`, 1 cell, 1 root, no index, no CRC). It does
/// NOT support refs, exotic cells, or multi-cell trees — anything beyond a
/// single flat body cell is out of scope and would need a real cell tree.
///
/// The output is verified two ways (see `TonCellBuilderTests`): the deposit
/// constant is reproduced byte-for-byte, and a burn body round-trips back
/// through `TonBocParser`/`TonMessageBodyDecoder` to the same op / amount /
/// address. The burn vector also byte-matches the reference `@ton/core` /
/// `pytoniq-core` serialisers.
final class TonCellBuilder {
    /// Bit payload, most-significant-bit first within each conceptual byte —
    /// matching `TonBitString`'s addressing in the decoder.
    private var bits: [Bool] = []

    /// A single ordinary cell stores at most 1023 data bits.
    private static let maxBits = 1023

    init() {}

    var bitCount: Int { bits.count }

    /// Store `value` as `count` big-endian bits. `count` must be in `0...64`
    /// (every field this builder writes — ops, query ids — fits in 64 bits).
    @discardableResult
    func storeUInt(_ value: UInt64, bits count: Int) throws -> TonCellBuilder {
        guard count >= 0, count <= 64 else { throw TonCellBuilderError.valueTooLarge }
        if count < 64 {
            // Reject values that don't fit in `count` bits so a too-large op /
            // query id surfaces here instead of silently truncating.
            guard value >> UInt64(count) == 0 else { throw TonCellBuilderError.valueTooLarge }
        }
        guard bits.count + count <= Self.maxBits else { throw TonCellBuilderError.cellOverflow }
        if count == 0 { return self }
        for index in stride(from: count - 1, through: 0, by: -1) {
            bits.append((value >> UInt64(index)) & 1 == 1)
        }
        return self
    }

    /// Store a single bit (used for the `Maybe ^Cell` discriminator and the
    /// `addr_std` anycast flag).
    @discardableResult
    func storeBit(_ value: Bool) throws -> TonCellBuilder {
        guard bits.count + 1 <= Self.maxBits else { throw TonCellBuilderError.cellOverflow }
        bits.append(value)
        return self
    }

    /// Store a TON `Coins` / `VarUInteger 16` value:
    /// `var_uint$_ len:(## 4) value:(uint (len * 8))`.
    ///
    /// `amount` is an unsigned decimal string (jetton amounts can exceed
    /// `UInt64`, so a string keeps us BigInt-free, matching the decoder's
    /// `loadCoins`). A zero amount encodes as a 4-bit `0` length with no value
    /// bits.
    @discardableResult
    func storeCoins(_ amount: String) throws -> TonCellBuilder {
        let bytes = try Self.bigEndianBytes(decimal: amount)
        let length = bytes.count
        // VarUInteger 16 ⇒ len fits in 4 bits ⇒ at most 15 bytes (120 bits).
        guard length <= 15 else { throw TonCellBuilderError.valueTooLarge }
        try storeUInt(UInt64(length), bits: 4)
        for byte in bytes {
            try storeUInt(UInt64(byte), bits: 8)
        }
        return self
    }

    /// Store a standard internal `MsgAddress` (`addr_std$10`) for a raw TON
    /// address (`workchain:hex`). Used for the burn's `response_destination`.
    @discardableResult
    func storeAddress(rawAddress: String) throws -> TonCellBuilder {
        let (workchain, hash) = try Self.parseRawAddress(rawAddress)
        // addr_std$10 anycast:(Maybe = nothing) workchain_id:int8 address:bits256
        try storeUInt(0b10, bits: 2)
        try storeBit(false) // no anycast
        try storeUInt(UInt64(UInt8(bitPattern: workchain)), bits: 8)
        for byte in hash {
            try storeUInt(UInt64(byte), bits: 8)
        }
        return self
    }

    /// Serialise this single cell into a canonical BOC and base64-encode it.
    /// Layout: magic `b5ee9c72`, flags = size_bytes(1) with no idx/crc/cache,
    /// off_bytes 1, cells 1, roots 1, absent 0, tot_cells_size, root index 0,
    /// then the one cell's `d1 d2 data`. No CRC trailer (the decoder treats CRC
    /// as optional; omitting it matches the `@ton/core`/`pytoniq` default BOC).
    func toBocBase64() throws -> String {
        let cell = try serializeCell()
        var boc: [UInt8] = [0xb5, 0xee, 0x9c, 0x72]
        let sizeBytes: UInt8 = 1
        let offBytes: UInt8 = 1
        boc.append(sizeBytes)        // flags: no idx/crc/cache, size_bytes = 1
        boc.append(offBytes)         // off_bytes
        boc.append(0x01)             // cells count = 1
        boc.append(0x01)             // roots count = 1
        boc.append(0x00)             // absent count = 0
        guard cell.count <= 0xff else { throw TonCellBuilderError.cellOverflow }
        boc.append(UInt8(cell.count)) // total cells size
        boc.append(0x00)             // root index = 0
        boc.append(contentsOf: cell)
        return Data(boc).base64EncodedString()
    }

    // MARK: - Private

    /// Build the `d1 d2 data` serialised form of this ordinary, ref-less cell.
    private func serializeCell() throws -> [UInt8] {
        let bitLen = bits.count
        let fullBytes = bitLen / 8
        let remainder = bitLen % 8

        var data = [UInt8](repeating: 0, count: (bitLen + 7) / 8)
        for (index, bit) in bits.enumerated() where bit {
            data[index / 8] |= 1 << (7 - (index % 8))
        }

        let d1: UInt8 = 0 // refs = 0, ordinary (not exotic), no hashes, level 0
        let d2: UInt8
        if remainder == 0 {
            d2 = UInt8(fullBytes * 2)
        } else {
            // Non-aligned cell: set the augmentation marker bit (a `1`
            // immediately after the real bits) so the decoder can recover the
            // exact bit length. `data` already has the marker position as the
            // next free bit; set it explicitly.
            let markerIndex = bitLen
            data[markerIndex / 8] |= 1 << (7 - (markerIndex % 8))
            d2 = UInt8(fullBytes * 2 + 1)
        }

        return [d1, d2] + data
    }

    /// Parse a raw `workchain:hex` TON address into its int8 workchain and the
    /// 32-byte account hash. Accepts the canonical raw form WalletCore emits via
    /// `TONAddressConverter`; user-friendly (base64) forms are normalised first.
    private static func parseRawAddress(_ address: String) throws -> (Int8, [UInt8]) {
        let raw: String
        if address.contains(":") {
            raw = address
        } else if let back = rawForm(ofFriendly: address) {
            // User-friendly (base64) form: normalise to raw via WalletCore.
            raw = back
        } else {
            throw TonCellBuilderError.invalidAddress
        }

        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let workchain = Int8(parts[0]) else {
            throw TonCellBuilderError.invalidAddress
        }
        let hex = String(parts[1])
        guard hex.count == 64, let hash = hexBytes(hex), hash.count == 32 else {
            throw TonCellBuilderError.invalidAddress
        }
        return (workchain, hash)
    }

    /// WalletCore can convert a friendly address back to raw via `toBoc` →
    /// `fromBoc`; but the simplest reliable path is: friendly → boc → raw.
    private static func rawForm(ofFriendly friendly: String) -> String? {
        guard let boc = TONAddressConverter.toBoc(address: friendly) else { return nil }
        return TONAddressConverter.fromBoc(boc: boc)
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// Convert an unsigned base-10 string into its minimal big-endian byte
    /// representation (no leading zero byte; `"0"` → `[]`). Rejects negatives
    /// and non-digits. Allocation-light long division by 256.
    private static func bigEndianBytes(decimal: String) throws -> [UInt8] {
        let trimmed = decimal.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw TonCellBuilderError.negativeValue }
        guard !trimmed.hasPrefix("-") else { throw TonCellBuilderError.negativeValue }
        guard trimmed.allSatisfy({ $0.isNumber }) else { throw TonCellBuilderError.negativeValue }

        // Strip leading zeros; an all-zero value is the empty byte array.
        var digits = Array(trimmed.drop(while: { $0 == "0" }).utf8).map { $0 - 48 }
        if digits.isEmpty { return [] }

        var bytesReversed: [UInt8] = []
        while !digits.isEmpty {
            var remainder = 0
            var quotient: [UInt8] = []
            quotient.reserveCapacity(digits.count)
            for digit in digits {
                let acc = remainder * 10 + Int(digit)
                let q = acc / 256
                remainder = acc % 256
                if !quotient.isEmpty || q != 0 {
                    quotient.append(UInt8(q))
                }
            }
            bytesReversed.append(UInt8(remainder))
            digits = quotient
        }
        return bytesReversed.reversed()
    }
}
