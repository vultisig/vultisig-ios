//
//  ValidatorBech32Preflight.swift
//  VultisigApp
//
//  Sanity-checks a Cosmos validator operator address (`terravaloper1…`)
//  before the MPC ceremony spends a signing round on a tx the chain will
//  reject post-broadcast. Mirrors the agent-app `requireValoper(...)` guard
//  at `vultiagent-app/src/services/cosmosTx.ts:1110-1140`.
//
//  Three checks, in order:
//    1. Bech32 decode succeeds (charset + checksum).
//    2. HRP matches the per-chain expected operator prefix (e.g.
//       `terravaloper` for both Terra phoenix-1 and TerraClassic
//       columbus-5).
//    3. The decoded data payload is exactly 20 bytes (the operator's
//       AccAddress equivalent; consensus pub keys are 32 bytes and would
//       slip past prefix-only validation).
//
//  Implements BIP-173 bech32 decode (32-symbol charset + polymod checksum)
//  inline rather than pulling a generic bech32 dependency. Future Cosmos
//  chains that adopt bech32m for valoper addresses would need the variant
//  flag — Terra uses classic bech32 today.
//

import Foundation

enum ValidatorBech32Preflight {

    enum ValidatorBech32Error: Error, LocalizedError, Equatable {
        case empty
        case badEncoding
        case wrongPrefix(actual: String, expected: String)
        case wrongPayloadLength(actual: Int, expected: Int)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Validator address is empty"
            case .badEncoding:
                return "Validator address is not valid bech32"
            case .wrongPrefix(let actual, let expected):
                return "Validator address prefix '\(actual)' does not match expected '\(expected)'"
            case .wrongPayloadLength(let actual, let expected):
                return "Validator address payload is \(actual) bytes, expected \(expected)"
            }
        }
    }

    /// Expected operator address payload length. Cosmos AccAddress + valoper
    /// share the same 20-byte (ripemd160(sha256(pubkey))) shape; consensus
    /// pubkeys (`*valconspub1…`) are 32 bytes and would otherwise pass a
    /// prefix-only check.
    private static let expectedPayloadLength = 20

    static func validate(_ address: String, for chain: Chain) throws {
        guard !address.isEmpty else { throw ValidatorBech32Error.empty }

        let expectedHrp = try CosmosStakingConfig.valoperHrp(for: chain)
        let decoded = try decode(address)

        guard decoded.hrp == expectedHrp else {
            throw ValidatorBech32Error.wrongPrefix(actual: decoded.hrp, expected: expectedHrp)
        }
        guard decoded.payload.count == expectedPayloadLength else {
            throw ValidatorBech32Error.wrongPayloadLength(
                actual: decoded.payload.count,
                expected: expectedPayloadLength
            )
        }
    }

    // MARK: - BIP-173 bech32 decode

    struct Decoded: Equatable {
        let hrp: String
        let payload: [UInt8]
    }

    /// BIP-173 charset.
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    /// Decodes a bech32 string (`<hrp>1<data><checksum>`) and returns the
    /// HRP plus the converted 8-bit payload. Throws `.badEncoding` on any
    /// charset / checksum / structure violation.
    static func decode(_ address: String) throws -> Decoded {
        let lowered = address.lowercased()
        // Mixed case is forbidden per BIP-173; if upper- and lower-case
        // characters both appear, the address is invalid.
        if lowered != address && address.uppercased() != address {
            throw ValidatorBech32Error.badEncoding
        }
        // Bech32 spec caps the full string at 90 chars; we keep that guard
        // but allow the agent-app's empirically observed valoper widths.
        guard lowered.count >= 8 && lowered.count <= 90 else {
            throw ValidatorBech32Error.badEncoding
        }
        guard let separatorIndex = lowered.lastIndex(of: "1") else {
            throw ValidatorBech32Error.badEncoding
        }
        let hrp = String(lowered[..<separatorIndex])
        let dataPart = String(lowered[lowered.index(after: separatorIndex)...])
        guard !hrp.isEmpty, dataPart.count >= 6 else {
            throw ValidatorBech32Error.badEncoding
        }
        for char in hrp where !(char >= "!" && char <= "~") {
            throw ValidatorBech32Error.badEncoding
        }

        // Map data chars → 5-bit values via the charset lookup.
        var values: [UInt8] = []
        values.reserveCapacity(dataPart.count)
        for char in dataPart {
            guard let index = charset.firstIndex(of: char) else {
                throw ValidatorBech32Error.badEncoding
            }
            values.append(UInt8(index))
        }

        guard verifyChecksum(hrp: hrp, data: values) else {
            throw ValidatorBech32Error.badEncoding
        }

        // Drop the 6-byte checksum and convert the remaining 5-bit groups
        // back to 8-bit bytes.
        let payload5Bit = Array(values.dropLast(6))
        guard let payload8Bit = convertBits(payload5Bit, from: 5, to: 8, pad: false) else {
            throw ValidatorBech32Error.badEncoding
        }
        return Decoded(hrp: hrp, payload: payload8Bit)
    }

    // MARK: - Polymod checksum (BIP-173)

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)
            for index in 0..<5 where ((top >> index) & 1) == 1 {
                chk ^= generator[index]
            }
        }
        return chk
    }

    /// Expands the HRP into the prefix the polymod step consumes:
    /// high-bits || 0 || low-bits.
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        var result: [UInt8] = bytes.map { $0 >> 5 }
        result.append(0)
        result.append(contentsOf: bytes.map { $0 & 0x1f })
        return result
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    /// Converts a contiguous bit-stream between bit widths. Used here to
    /// drop the 5→8 bit packing the data part uses. Returns nil when the
    /// input cannot be cleanly converted (input bits don't divide into the
    /// output width and `pad` is false).
    private static func convertBits(_ data: [UInt8], from fromBits: Int, to toBits: Int, pad: Bool) -> [UInt8]? {
        var acc: Int = 0
        var bits: Int = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            if Int(value) >> fromBits != 0 { return nil }
            acc = ((acc << fromBits) | Int(value)) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        return result
    }
}
