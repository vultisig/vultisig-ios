//
//  Array.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/08/2025.
//

import Foundation

extension Array {
    func uniqueBy<T: Hashable>(_ transform: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert(transform($0)).inserted }
    }

    public subscript(safe index: Int) -> Element? {
        guard index >= 0, index < endIndex else {
            return nil
        }

        return self[index]
    }

    /// Splits into consecutive slices of at most `size` elements each — the
    /// last slice may be shorter. Empty input always yields no chunks,
    /// regardless of `size`; a non-positive `size` on non-empty input
    /// returns the whole array as one slice, avoiding an infinite loop.
    func chunked(into size: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
