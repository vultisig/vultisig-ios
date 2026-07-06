//
//  RippleDestinationTag.swift
//  VultisigApp
//

import Foundation

/// Destination-tag rules for XRP keysign payloads.
///
/// The tag travels in the generic `KeysignPayload.memo` slot as a canonical
/// uint32 decimal — the wire contract every Vultisig platform's Ripple
/// signing-input builder already understands (numeric memo → wallet-core
/// `destinationTag`). "Canonical" matters: leading zeros or whitespace make
/// the SDK's strict round-trip parse diverge from the lenient mobile parses,
/// which would split the keysign committee's pre-image hashes.
///
/// The payload memo must therefore be empty or a canonical uint32 decimal;
/// anything else is rejected on BOTH sides of the ceremony (initiator and
/// co-signer both funnel through `RippleHelper.getPreSignedInputData`).
/// This intentionally removes the legacy non-numeric-memo → on-chain
/// `Memos` blob path: a tag-typo there meant an uncredited exchange deposit.
enum RippleDestinationTag {

    /// Strict canonical parse: ASCII digits only, no sign, no whitespace,
    /// no leading zeros (except the value "0" itself), and within uint32
    /// bounds. The round-trip comparison enforces all of that at once.
    static func parseCanonical(_ string: String) -> UInt32? {
        guard let value = UInt32(string), String(value) == string else {
            return nil
        }
        return value
    }

    /// Parse a destination tag: canonical AND non-zero. Zero is rejected
    /// because wallet-core's proto3 scalar can't express "present with value
    /// 0" — the payment would sign untagged on every platform while the UI
    /// displayed a tag. (XLS-5d allows tag 0 on-chain; no wallet-core-based
    /// signer can produce it, so failing loudly beats signing dishonestly.)
    static func parseTag(_ string: String) -> UInt32? {
        guard let value = parseCanonical(string), value != 0 else {
            return nil
        }
        return value
    }

    /// Validates the memo slot of an XRP keysign payload. Returns the tag
    /// (or `nil` for an empty memo) or throws `RippleMemoError.invalidMemo`.
    static func validatePayloadMemo(_ memo: String?) throws -> UInt32? {
        guard let memo, !memo.isEmpty else { return nil }
        guard let tag = parseTag(memo) else {
            throw RippleMemoError.invalidMemo(memo)
        }
        return tag
    }
}

/// Typed, user-presentable rejection for XRP payloads whose memo slot
/// doesn't satisfy the destination-tag wire contract. Surfaced by the
/// initiator when the ceremony is prepared and by co-signers before they
/// join it (dApp/deeplink-originated payloads included).
enum RippleMemoError: LocalizedError, Equatable {
    case invalidMemo(String)

    var errorDescription: String? {
        switch self {
        case .invalidMemo:
            return "xrpMemoNotDestinationTagError".localized
        }
    }
}
