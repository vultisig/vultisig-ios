//
//  SwapKitDestinationTag.swift
//  VultisigApp
//

import Foundation

/// What one source says about an XRP destination tag.
///
/// "States no tag" and "states a tag this client cannot read" are different answers, and a
/// `UInt64?` forces them to collapse — which sends a tag-less deposit to an address where the
/// tag is what identifies the depositor.
enum SwapKitDestinationTag: Hashable {
    case absent
    case tag(UInt64)
    /// A value that is not a `UInt64`, or more than one `dt` parameter. Two answers is not one
    /// answer, and picking one is a guess.
    case unreadable(reason: String)

    /// `.unreadable` yields nil so resolution behaves as it did before this type existed;
    /// refusing such a response is the agreement guard's job, not resolution's.
    var usableTag: UInt64? {
        guard case .tag(let value) = self else { return nil }
        return value
    }

    /// SwapKit sends the tag as a number or as a numeric string. Present-but-neither is
    /// `.unreadable`, never `.absent`.
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
