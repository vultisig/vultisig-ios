//
//  DataExntension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import OSLog
import CommonCrypto
import WalletCore
import CryptoKit
import BigInt
import Foundation

extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }

        return Data(hash)
    }

    static func clampThenUniformScalar(from seed: Data) -> Data? {
        guard let clamped = ed25519ClampedScalar(from: seed) else { return nil }
        return ed25519UniformFromLittleEndianScalar(clamped)
    }

    static func ed25519UniformFromLittleEndianScalar(_ littleEndianScalar: Data) -> Data? {
        guard littleEndianScalar.count == 32 else { return nil }
        // ed25519 group order L (big-endian hex)
        let Lhex = "1000000000000000000000000000000014DEF9DEA2F79CD65812631A5CF5D3ED"
        guard let L = BigUInt(Lhex, radix: 16) else { return nil }

        // BigUInt initializer expects big-endian bytes, so reverse
        let be = Data(littleEndianScalar.reversed())
        let x = BigUInt(be)               // value of scalar
        let r = x % L                     // reduce mod L

        // serialize r as 32-byte big-endian, pad if needed, then return little-endian
        let rBE = r.serialize()
        let paddedBE = (Data(repeating: 0, count: Swift.max(0, 32 - rBE.count)) + rBE)
        return Data(paddedBE.reversed())
    }

    static func ed25519ClampedScalar(from seed: Data) -> Data? {
        guard seed.count == 32 else { return nil }
        let digest = SHA512.hash(data: seed)
        var scalar = Data(digest.prefix(32)) // little-endian per spec
        scalar[0] &= 0xF8
        scalar[31] &= 0x3F
        scalar[31] |= 0x40
        return scalar
    }
}
