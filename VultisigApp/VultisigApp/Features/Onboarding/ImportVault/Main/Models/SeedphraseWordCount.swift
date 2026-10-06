//
//  SeedphraseWordCount.swift
//  VultisigApp
//

import Foundation

enum SeedphraseWordCount {
    /// Every mnemonic length BIP39 defines.
    static let supported = [12, 15, 18, 21, 24]

    static func isSupported(_ count: Int) -> Bool {
        supported.contains(count)
    }

    /// Smallest supported length that fits `count`, used for the "n/max" counter.
    static func targetLength(for count: Int) -> Int {
        supported.first { $0 >= count } ?? supported[supported.count - 1]
    }
}
