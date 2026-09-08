//
//  SwapKitDestinationTag.swift
//  VultisigApp
//

import Foundation

/// What one source says about an XRP destination tag.
///
/// The tag is half the destination: a shared exchange address routes a deposit to an
/// account by tag, so "states no tag" and "states a tag this client cannot read" are
/// different answers that must never collapse into each other. A two-state `UInt64?`
/// forces exactly that collapse, and a fail-closed guard built on it reads an unreadable
/// tag as a tag-less payment — which credits nobody.
enum SwapKitDestinationTag: Hashable {
    /// The source says nothing: the field is absent or null, or the address carries no
    /// tag suffix.
    case absent
    /// The source states exactly one readable tag.
    case tag(UInt64)
    /// The source states something that is not one readable tag — a value that is not a
    /// `UInt64`, or more than one `dt` parameter. Two answers is not one answer, and
    /// picking one of them is a guess that misroutes a deposit.
    case unreadable(reason: String)

    /// The tag to use, or nil when there is none to use.
    ///
    /// `.unreadable` yields nil so the resolution helpers behave exactly as they did
    /// before this type existed. Refusing such a response is the agreement guard's job,
    /// not theirs — resolution answers "what would we use", validation answers "may we
    /// use this response at all".
    var usableTag: UInt64? {
        guard case .tag(let value) = self else { return nil }
        return value
    }

    /// Read a tag SwapKit may send as a number or as a numeric string (`meta.affiliateFee`
    /// arrives string-wrapped despite being numeric, so both shapes are accepted). A key
    /// that is present but holds neither is `.unreadable`, never `.absent`.
    static func decoded<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> SwapKitDestinationTag {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) == false else {
            return .absent
        }
        if let intTag = try? container.decode(UInt64.self, forKey: key) {
            return .tag(intTag)
        }
        if let stringTag = try? container.decode(String.self, forKey: key) {
            guard let parsed = UInt64(stringTag) else {
                return .unreadable(reason: "\"\(stringTag)\" is not a destination tag")
            }
            return .tag(parsed)
        }
        return .unreadable(reason: "value is neither a number nor a numeric string")
    }
}
