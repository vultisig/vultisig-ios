//
//  Bech32TestUtils.swift
//  VultisigAppTests
//
//  Shared bech32 encoder helpers extracted out of `ValidatorBech32PreflightTests`
//  so suites that need a valid `terravaloper1…` address — e.g. the staking
//  resolver tests — don't have to inline the encoder. Kept fileprivate-free
//  here so `Bech32TestUtils.makeValoperAddress(...)` reads cleanly at the
//  call site.
//

import Foundation

enum Bech32TestUtils {
    /// Builds a checksum-valid bech32 address for the given hrp by
    /// hashing a deterministic 20-byte payload (`[0, 1, 2, ..., 19]`).
    static func makeValoperAddress(hrp: String = "terravaloper", payloadLength: Int = 20) -> String {
        let payload = (0..<payloadLength).map { UInt8($0 & 0xff) }
        return encodeBech32(hrp: hrp, payload: payload)
    }

    /// Public bech32 encoder — the same code that lives in
    /// `ValidatorBech32PreflightTests` was extracted here verbatim so any
    /// suite can construct valid addresses without duplicating the
    /// polymod table.
    static func encodeBech32(hrp: String, payload: [UInt8]) -> String {
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let data5Bit = convertBits(payload, from: 8, to: 5, pad: true)
        let checksum = createChecksum(hrp: hrp, data: data5Bit)
        let combined = data5Bit + checksum
        return hrp + "1" + String(combined.map { charset[Int($0)] })
    }

    private static func convertBits(_ data: [UInt8], from fromBits: Int, to toBits: Int, pad: Bool) -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad && bits > 0 {
            result.append(UInt8((acc << (toBits - bits)) & maxv))
        }
        return result
    }

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + Array(repeating: UInt8(0), count: 6)
        let mod = polymod(values) ^ 1
        return (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 0x1f) }
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        var out: [UInt8] = bytes.map { $0 >> 5 }
        out.append(0)
        out.append(contentsOf: bytes.map { $0 & 0x1f })
        return out
    }

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
}
