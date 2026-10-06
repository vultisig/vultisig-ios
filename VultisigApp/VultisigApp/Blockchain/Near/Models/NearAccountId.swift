//
//  NearAccountId.swift
//  VultisigApp
//

import Foundation

/// NEAR account-ID grammar (docs.near.org/protocol/accounts-contracts/account-id):
/// 2–64 lowercase letters, digits and `.`, `-`, `_`, no leading, trailing or doubled separator.
/// Not WalletCore's check: it rejects named accounts and accepts the `0x…` / `0s…`
/// families, which are other accounts than the implicit one they resemble.
enum NearAccountId {

    /// Lowest-common-denominator named form: alphanumeric groups joined by one
    /// separator, with `.` delimiting the domain-like segments.
    private static let named = regex("^(([a-z0-9]+[-_])*[a-z0-9]+\\.)*([a-z0-9]+[-_])*[a-z0-9]+\\z")

    /// Implicit accounts ARE the lowercase hex form of an Ed25519 public key.
    private static let implicit = regex("^[0-9a-f]{64}\\z")

    /// `0x…` (NEP-518) and `0s…` (NEP-616) address families this transfer path
    /// cannot address.
    private static let unsupportedHexPrefixed = regex("^(0x|0s)[0-9a-f]{40}\\z")

    /// The implicit account of the all-zero key: valid, with no known private key.
    private static let burnAccount = String(repeating: "0", count: 64)

    private static let minimumLength = 2
    private static let maximumLength = 64

    static func isImplicit(_ accountId: String) -> Bool {
        matches(implicit, accountId)
    }

    /// Whether funds sent to `accountId` are unspendable.
    static func isBurnAccount(_ accountId: String) -> Bool {
        accountId == burnAccount
    }

    static func isValid(_ accountId: String) -> Bool {
        guard accountId.count >= minimumLength, accountId.count <= maximumLength else {
            return false
        }
        if isImplicit(accountId) {
            return true
        }
        if matches(unsupportedHexPrefixed, accountId) {
            return false
        }
        return matches(named, accountId)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals in this file; a compile failure is a
        // programmer error, not a runtime condition to recover from.
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid NEAR account-id pattern: \(pattern)")
        }
        return regex
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
