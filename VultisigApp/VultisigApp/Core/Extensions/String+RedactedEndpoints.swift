//
//  String+RedactedEndpoints.swift
//  VultisigApp
//

import Foundation

extension String {

    /// The same text, with every URL reduced to `scheme://host[:port]`.
    ///
    /// Chain errors are shown to the user, and users screenshot them into
    /// Discord and GitHub issues when asking for help. A custom RPC endpoint can
    /// carry a hosted provider's API key in its path or query string — QuickNode,
    /// Alchemy and Ankr all issue URLs shaped that way — so a message that
    /// embeds one turns a support screenshot into a credential disclosure.
    ///
    /// Only the credential-bearing components go. The scheme, host and port stay
    /// because they are what lets someone recognise *which* endpoint the error is
    /// about, and every other word of the message is left exactly as the chain
    /// wrote it: "insufficient gas", "object version conflict" and "already
    /// processed" are the difference between a user who can act and a user who
    /// files a ticket.
    ///
    /// **Fails closed.** Anything URL-shaped that cannot be parsed is replaced
    /// wholesale rather than passed through, because the reason it did not parse
    /// is not knowable here and the cost of guessing wrong is a leaked key.
    ///
    /// The result is **user-facing**: the fallback marker is localized, so it
    /// reads in the user's language. Do not log this value — log the original
    /// privately and display this, which is what `KeysignViewModel` does. A
    /// localized string in a log is worse than no redaction, because support
    /// then cannot match on it.
    func redactingEndpointCredentials() -> String {
        guard let detector = Self.urlDetector, !isEmpty else { return self }

        let matches = detector.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        guard !matches.isEmpty else { return self }

        // Built in one forward pass from the immutable original. Mutating in
        // place would invalidate every index still to be used, and would be
        // quadratic on a message carrying many URLs.
        var result = ""
        var cursor = startIndex

        for match in matches {
            guard let range = Range(match.range, in: self), range.lowerBound >= cursor else { continue }
            result += self[cursor..<range.lowerBound]
            result += Self.redacted(String(self[range]))
            cursor = range.upperBound
        }

        result += self[cursor...]
        return result
    }

    /// `scheme://host[:port]` for one matched candidate, plus any sentence
    /// punctuation that the greedy match swallowed.
    private static func redacted(_ candidate: String) -> String {
        // The match runs to whitespace so that a credential can never fall
        // outside it. That also picks up trailing punctuation belonging to the
        // sentence, which is put back — safely, because everything after the
        // authority is discarded regardless.
        let trailing = candidate.suffix(while: { Self.sentencePunctuation.contains($0) })
        let trimmed = String(candidate.dropLast(trailing.count))

        // Trimmed first, so sentence punctuation is preserved. Then the whole
        // candidate, because a bare IPv6 URL legitimately ends in `]` and would
        // otherwise be trimmed into something unparseable.
        if !trimmed.isEmpty, let redacted = Self.authority(of: trimmed) {
            return redacted + trailing
        }
        if let redacted = Self.authority(of: candidate) {
            return redacted
        }

        // URL-shaped but unparseable. Anything could be in there.
        return Self.redactionMarker + trailing
    }

    /// `scheme://host[:port]` for a parseable URL, `nil` otherwise.
    private static func authority(of url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              let host = components.host, !host.isEmpty else {
            return nil
        }

        // An IPv6 literal needs its brackets, or the result is not a URL any
        // more — but `URLComponents.host` may already include them, so adding a
        // pair unconditionally produces `[[::1]]`.
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        var redacted = "\(scheme)://\(authority)"
        if let port = components.port {
            redacted += ":\(port)"
        }

        let carriedMore = components.user != nil
            || components.password != nil
            || components.query != nil
            || components.fragment != nil
            || (!components.path.isEmpty && components.path != "/")

        return carriedMore ? redacted + "/…" : redacted
    }

    /// Shown in place of a URL that could not be parsed.
    ///
    /// Computed rather than stored. It is read at most once per failed
    /// broadcast, so caching buys nothing, while a `static let` would fix the
    /// string for the whole process lifetime.
    ///
    /// Today the two behave identically — `SettingsOptionsStore` notes that a
    /// language change "must restart the app to have effect" — so this is not
    /// fixing a live bug. It is the form that stays correct if in-session
    /// switching ever lands.
    private static var redactionMarker: String {
        "redactedEndpoint".localized
    }

    /// Characters that end a sentence rather than a URL. Trimmed before parsing
    /// and restored afterwards.
    private static let sentencePunctuation = Set<Character>(".,;:!?)]}>\"'")

    /// Matches `scheme://` and everything up to the next whitespace.
    ///
    /// Deliberately greedy: a path, query or userinfo is exactly what has to be
    /// removed, so it must be inside the match. Stopping at quotes would leave
    /// the tail of a key like `?apiKey=ABC'DEF` sitting in the message.
    private static let urlDetector: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "[a-zA-Z][a-zA-Z0-9+.-]*://\\S+")
    }()

    /// The longest suffix whose every character satisfies `predicate`.
    private func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
