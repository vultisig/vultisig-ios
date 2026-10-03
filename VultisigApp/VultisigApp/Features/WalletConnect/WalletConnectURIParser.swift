//
//  WalletConnectURIParser.swift
//  VultisigApp
//

import Foundation

enum WalletConnectURIParser {
    static func normalizedURI(from url: URL) -> String? {
        normalizedURI(from: url.absoluteString)
    }

    static func normalizedURI(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed), components.scheme?.lowercased() == "wc" {
            return trimmed
        }

        guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
        let scheme = trimmed[..<colonIndex]
        guard scheme.caseInsensitiveCompare("wc") == .orderedSame else { return nil }

        return trimmed
    }
}
