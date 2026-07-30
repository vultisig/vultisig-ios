//
//  DERSignature.swift
//  VultisigApp
//
//  Created by Johnny Luo on 11/12/2024.
//

import Foundation
import BigInt

func encodeCanonicalDERSignature(r: [UInt8], s: [UInt8]) -> Data {
    let curveOrder = Data(hex: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141")
    func derInteger(_ value: Data) -> Data {
        var value = value

        // Strip non-essential leading zero bytes first. `r` arrives as a
        // fixed 32-byte scalar straight from the raw signature, not a
        // minimal-length big-endian value like `s` (which is already minimal
        // via BigUInt.serialize() below) — encoding it verbatim adds padding
        // a strict node's DER check rejects as non-canonical whenever the
        // true value needs fewer than 32 bytes.
        while value.count > 1 && value.first == 0x00 && value[value.index(after: value.startIndex)] < 0x80 {
            value.removeFirst()
        }

        // Ensure the value is positive (prefix with 0x00 if highest bit is set)
        if value.first! >= 0x80 {
            value.insert(0x00, at: 0)
        }

        return Data([0x02, UInt8(value.count)]) + value
    }

    // Ensure S is canonical: If S > N/2, use N - S
    let sBigInt = BigUInt(Data(s))
    let curveN = BigUInt(curveOrder)
    let halfCurveN = curveN / 2

    let canonicalS = sBigInt > halfCurveN ? curveN - sBigInt : sBigInt
    let canonicalSData = canonicalS.serialize()

    let rEncoded = derInteger(Data(r))
    let sEncoded = derInteger(canonicalSData)

    let sequenceLength = rEncoded.count + sEncoded.count
    return Data([0x30, UInt8(sequenceLength)]) + rEncoded + sEncoded
}
