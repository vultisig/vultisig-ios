//
//  TonAddressBounceability.swift
//  VultisigApp
//

import Foundation

/// A TON user-friendly address encodes bounce intent in the first byte of its
/// base64url payload (the "flag" tag byte: 0x11 bounceable / 0x51
/// non-bounceable on mainnet, +0x80 for testnet). A raw `workchain:hash`
/// address carries no such byte, so it encodes no bounce intent at all.
enum TonAddressBounceability {

    private static let addressByteCount = 36
    private static let nonBounceableFlagBit: UInt8 = 0x40
    // 0x11/0x51 mainnet, 0x91/0xD1 testnet. A payload of the right length but
    // any other tag is not a TON friendly address, so its intent is unknown.
    private static let validTags: Set<UInt8> = [0x11, 0x51, 0x91, 0xD1]
    private static let addressCharCount = 48
    private static let urlSafeBase64Chars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// The bounce flag encoded in a TON user-friendly address, or `nil` when the
    /// address is raw or is not a canonical friendly address (wrong length,
    /// non-URL-safe characters, bad tag, or bad checksum).
    static func isBounceable(_ address: String) -> Bool? {
        guard !address.contains(":"),
              address.count == addressCharCount,
              address.allSatisfy(urlSafeBase64Chars.contains),
              let data = decodeBase64Url(address),
              data.count == addressByteCount else {
            return nil
        }
        let bytes = [UInt8](data)
        guard validTags.contains(bytes[0]) else { return nil }
        // Bytes 34-35 hold the CRC16-CCITT of the preceding 34; a mismatch means
        // a corrupted address whose bounce intent can't be trusted.
        let checksum = UInt16(bytes[34]) << 8 | UInt16(bytes[35])
        guard crc16(bytes[0..<34]) == checksum else { return nil }
        return (bytes[0] & nonBounceableFlagBit) == 0
    }

    private static func crc16(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    private static func decodeBase64Url(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
