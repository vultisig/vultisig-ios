//
//  BigUIntExtensions.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import BigInt

extension BigUInt {
    /// Initializes a new BigUInt from an Int.
    /// - Parameter value: The Int value to convert. Must be non-negative.
    public init(_ value: Int) {
        precondition(value >= 0, "BigUInt cannot represent negative values")
        self.init(words: [Word(value)])
    }

    /// Initializes a new BigUInt from a String.
    /// - Parameter string: The String representation of the number.
    /// - Parameter radix: The base of the number in the string. Default is 10.
    public init?(_ string: String, radix: Int = 10) {
        guard !string.isEmpty else { return nil }
        self.init()

        var bigInt = BigUInt()
        for character in string {
            guard let digit = Int(String(character), radix: radix) else { return nil }
            bigInt = bigInt.multiplied(by: BigUInt(radix)) + BigUInt(digit)
        }

        self = bigInt
    }
}
