//
//  RippleXAddress.swift
//  VultisigApp
//

import Foundation

/// Decoder for XRPL X-addresses (XLS-5d): a base58check envelope bundling a
/// classic account ID with an optional 32-bit destination tag. WalletCore
/// validates and signs X-addresses inside its Ripple signer but exposes no
/// Swift codec, so the Send form decodes them here to autofill the
/// Destination Tag field and normalize the outgoing payload to the classic
/// `r...` address.
///
/// Layout of the checked payload (31 bytes):
///   [0-1]   network prefix — mainnet 0x05 0x44 ("X..."), testnet 0x04 0x93 ("T...")
///   [2-21]  20-byte account ID
///   [22]    tag flag — 0: no tag, 1: 32-bit tag, >= 2: reserved (64-bit), rejected
///   [23-30] tag, little-endian; the upper 4 bytes are reserved and must be zero
/// followed by a 4-byte double-SHA256 checksum over the payload.
struct RippleXAddress: Equatable {
    /// Classic `r...` address encoded from the embedded account ID.
    let classicAddress: String
    /// Embedded destination tag. `nil` when the flag byte says "no tag";
    /// tag 0 is a real tag, distinct from no tag.
    let tag: UInt32?

    enum DecodeError: Error, Equatable {
        /// Input isn't a well-formed mainnet X-address: wrong alphabet,
        /// failed checksum, wrong payload length, or unknown prefix.
        case notAnXAddress
        /// Well-formed X-address carrying the testnet prefix — rejected
        /// because the app only signs mainnet payments.
        case testnetAddress
        /// Tag flag >= 2 (reserved for 64-bit tags) or nonzero reserved
        /// bytes alongside a 32-bit tag.
        case unsupportedTag
    }

    private static let checkedPayloadLength = 31
    private static let classicAddressVersionByte: UInt8 = 0x00

    static func decode(_ input: String) throws -> RippleXAddress {
        guard let payload = XRPLBase58.decodeChecked(input),
              payload.count == checkedPayloadLength else {
            throw DecodeError.notAnXAddress
        }

        let bytes = [UInt8](payload)
        switch (bytes[0], bytes[1]) {
        case (0x05, 0x44): // mainnet, renders as "X..."
            break
        case (0x04, 0x93): // testnet, renders as "T..."
            throw DecodeError.testnetAddress
        default:
            throw DecodeError.notAnXAddress
        }

        let accountID = Data(bytes[2..<22])
        let tag: UInt32?
        switch bytes[22] {
        case 0:
            // No tag: all 8 reserved bytes must be zero.
            guard bytes[23...30].allSatisfy({ $0 == 0 }) else {
                throw DecodeError.notAnXAddress
            }
            tag = nil
        case 1:
            // 32-bit tag, little-endian; upper 4 reserved bytes must be zero.
            guard bytes[27...30].allSatisfy({ $0 == 0 }) else {
                throw DecodeError.unsupportedTag
            }
            tag = UInt32(bytes[23])
                | (UInt32(bytes[24]) << 8)
                | (UInt32(bytes[25]) << 16)
                | (UInt32(bytes[26]) << 24)
        default:
            throw DecodeError.unsupportedTag
        }

        return RippleXAddress(
            classicAddress: encodeClassicAddress(accountID: accountID),
            tag: tag
        )
    }

    /// Encodes a 20-byte account ID as a classic `r...` address
    /// (version byte 0x00 + account ID, base58check, XRPL alphabet).
    private static func encodeClassicAddress(accountID: Data) -> String {
        XRPLBase58.encodeChecked(Data([classicAddressVersionByte]) + accountID)
    }
}

/// Base58 with the XRPL dictionary — NOT the Bitcoin one, so WalletCore's
/// `Base58` can't be reused. Checked variants append/verify a 4-byte
/// double-SHA256 checksum.
private enum XRPLBase58 {
    static let alphabet: [UInt8] = Array("rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz".utf8)
    /// The zero digit of the alphabet ("r") — leading zero bytes map to it.
    static let zeroDigit: UInt8 = 0x72

    private static let digitLookup: [Int8] = {
        var table = [Int8](repeating: -1, count: 128)
        for (index, character) in alphabet.enumerated() {
            table[Int(character)] = Int8(index)
        }
        return table
    }()

    static func decodeChecked(_ string: String) -> Data? {
        guard let decoded = decode(string), decoded.count > 4 else { return nil }
        let payload = Data(decoded.prefix(decoded.count - 4))
        let checksum = Data(decoded.suffix(4))
        guard payload.sha256().sha256().prefix(4) == checksum else { return nil }
        return payload
    }

    static func encodeChecked(_ payload: Data) -> String {
        encode(payload + payload.sha256().sha256().prefix(4))
    }

    static func decode(_ string: String) -> Data? {
        let input = Array(string.utf8)
        guard !input.isEmpty else { return nil }

        // Big-number decode: accumulate base-58 digits into base-256 bytes
        // (little-endian while accumulating).
        var bytes: [UInt8] = []
        for character in input {
            guard character < 128, digitLookup[Int(character)] >= 0 else { return nil }
            var carry = Int(digitLookup[Int(character)])
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        let leadingZeros = input.prefix(while: { $0 == zeroDigit }).count
        return Data([UInt8](repeating: 0, count: leadingZeros) + bytes.reversed())
    }

    static func encode(_ data: Data) -> String {
        // Big-number encode: base-256 bytes into base-58 digits
        // (little-endian while accumulating).
        var digits: [UInt8] = []
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                carry += Int(digits[index]) << 8
                digits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        let leadingZeros = data.prefix(while: { $0 == 0 }).count
        var characters = [UInt8](repeating: zeroDigit, count: leadingZeros)
        characters.append(contentsOf: digits.reversed().map { alphabet[Int($0)] })
        // The alphabet is pure ASCII, so this initializer cannot fail.
        return String(bytes: characters, encoding: .utf8) ?? ""
    }
}
