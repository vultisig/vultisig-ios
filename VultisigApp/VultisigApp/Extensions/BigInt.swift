//
//  BigInt.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/04/2024.
//

import Foundation
import BigInt

extension BigInt {
    /// Serializes the BigInt as a 32-byte Data object suitable for Ethereum (uint256).
    /// The serialization is big-endian without any sign indicator.
    func serializeForEvm() -> Data {
        let magnitudeData = self.magnitude.serialize()

        // Ensure the resulting Data is exactly 32 bytes
        var data = Data(repeating: 0, count: 32 - magnitudeData.count)
        data.append(magnitudeData)

        // If for any reason it's more than 32 bytes, truncate to the last 32 bytes
        if data.count > 32 {
            data = data.suffix(32)
        }

        return data
    }

    // the decimals must be truncaded otherwise the give us precisions errors
    func toDecimal(decimals: Int) -> Decimal {
        self.description.toDecimal().truncated(toPlaces: decimals)
    }

    func toDisplayDecimal(decimals: Int) -> Decimal {
        self.description.toDecimal() / pow(10, decimals)
    }
    /// Converts the BigInt value to wei (multiplies by 10^18).
    func toWei() -> BigInt {
        return self * BigInt(10).power(18)
    }
}
