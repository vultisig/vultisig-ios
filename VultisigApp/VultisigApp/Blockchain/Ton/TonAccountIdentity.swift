//
//  TonAccountIdentity.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Whether two TON address spellings name the same account.
///
/// One account has several textual spellings — raw `workchain:hash`, bounceable `EQ…`,
/// non-bounceable `UQ…`, and the base64 / base64url variants of both — and only the flag
/// byte and the trailing checksum separate `EQ` from `UQ`. String equality therefore
/// reports differences that do not exist, which matters wherever two independently
/// sourced addresses are cross-checked before money moves.
enum TonAccountIdentity {

    /// Canonicalising through the bounceable spelling collapses every form of one account
    /// onto a single string. Bounceability is deliberately not part of identity: the bounce
    /// flag that actually ships is decided by `BlockChainService` (forced on for swap
    /// deposits), not by the spelling a response happened to use.
    static func isSameAccount(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canonicalLeft = canonical(left), let canonicalRight = canonical(right) else {
            // Input that does not parse as a TON address names no account, and two values
            // that name no account do not name the same one. Answering "equal" for two
            // identical unparseable strings would let a guard built on this report
            // agreement about something that is not an address at all.
            return false
        }
        return canonicalLeft == canonicalRight
    }

    /// `toUserFriendly` accepts raw and user-friendly input alike and returns nil for
    /// anything that does not parse as a TON address.
    private static func canonical(_ address: String) -> String? {
        TONAddressConverter.toUserFriendly(address: address, bounceable: true, testnet: false)
    }
}
