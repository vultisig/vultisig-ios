//
//  KeychainReadResult.swift
//  VultisigApp
//

import Foundation
import Security

/// The outcome of a single Keychain read.
///
/// `SecItemCopyMatching` already distinguishes "there is no item for this key"
/// (`errSecItemNotFound`) from "the item could not be read" — a locked device,
/// a missing entitlement, a keychain the system refused to open. Returning
/// `Data?` throws that distinction away, and the two license opposite decisions:
/// absence says a value may safely be written, while an unreadable keychain says
/// a value may already be there. Where the stored item is key material, that is
/// the difference between saving a secret and destroying one.
///
/// Callers that genuinely do not need the distinction still have to say so, via
/// ``valueTreatingUnavailableAsAbsent``.
enum KeychainReadResult<Value> {

    /// The Keychain answered, and holds no item for this key.
    case absent

    /// The Keychain answered with the stored value.
    case present(Value)

    /// The Keychain could not answer. Whether an item exists is unknown.
    ///
    /// - Parameter status: the `OSStatus` the Security framework reported, or
    ///   `errSecDecode` when an item was returned but could not be interpreted
    ///   as the requested type.
    case unavailable(OSStatus)
}

extension KeychainReadResult {

    /// The stored value, treating an unreadable Keychain exactly like an absent
    /// item.
    ///
    /// Correct wherever the value is a cache or a convenience the caller can
    /// obtain again — a fast-vault password that cannot be read just means the
    /// user types it in. Wrong wherever `nil` would authorise a write, because
    /// a transient failure would then overwrite a value that is still there.
    /// Spelled out at the call site so that choice is visible in review.
    var valueTreatingUnavailableAsAbsent: Value? {
        switch self {
        case .present(let value):
            return value
        case .absent, .unavailable:
            return nil
        }
    }
}

extension KeychainReadResult: Equatable where Value: Equatable {}
