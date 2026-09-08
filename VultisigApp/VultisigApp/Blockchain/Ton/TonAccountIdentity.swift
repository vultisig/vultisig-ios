//
//  TonAccountIdentity.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Whether two TON address spellings name the same account. One account has several — raw
/// `workchain:hash`, `EQ…`, `UQ…`, and the base64 / base64url variants of both — so string
/// equality reports differences that do not exist.
enum TonAccountIdentity {

    /// Bounceability is deliberately not part of identity: the flag that ships is decided by
    /// `BlockChainService`, not by the spelling a response happened to use.
    static func isSameAccount(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canonicalLeft = canonical(left), let canonicalRight = canonical(right) else {
            // Two values that name no account do not name the same one.
            return false
        }
        return canonicalLeft == canonicalRight
    }

    /// Accepts raw and user-friendly input alike; nil for anything that is not a TON address.
    private static func canonical(_ address: String) -> String? {
        TONAddressConverter.toUserFriendly(address: address, bounceable: true, testnet: false)
    }
}
