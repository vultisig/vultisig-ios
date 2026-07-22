//
//  BigIntExtension.swift
//  VultisigApp
//

import BigInt

extension Array where Element == BigInt {
    /// Median of this array (already sorted ascending), or nil when empty. Averages the two
    /// central elements for an even-length array instead of picking a single upper-middle one.
    func median() -> BigInt? {
        guard !isEmpty else { return nil }
        let mid = count / 2
        if count % 2 == 0 {
            return (self[mid - 1] + self[mid]) / 2
        } else {
            return self[mid]
        }
    }
}
