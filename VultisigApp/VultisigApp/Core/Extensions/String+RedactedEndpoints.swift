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
    func redactingEndpointCredentials() -> String {
        guard let detector = Self.urlDetector, !isEmpty else { return self }

        let range = NSRange(startIndex..<endIndex, in: self)
        var result = self

        // Replace from the back so earlier ranges stay valid.
        for match in detector.matches(in: self, range: range).reversed() {
            guard let matched = Range(match.range, in: self) else { continue }
            let text = String(self[matched])
            guard let redacted = Self.redactedEndpoint(text), redacted != text else { continue }
            result.replaceSubrange(matched, with: redacted)
        }

        return result
    }

    /// `scheme://host[:port]`, plus a marker when anything was dropped.
    /// Returns `nil` when the match is not a URL with a host, so the original
    /// text is left alone rather than mangled.
    private static func redactedEndpoint(_ text: String) -> String? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }

        var redacted = "\(scheme)://\(host)"
        if let port = components.port {
            redacted += ":\(port)"
        }

        let carriedMore = components.user != nil
            || components.password != nil
            || components.query != nil
            || components.fragment != nil
            || !components.path.isEmpty && components.path != "/"

        return carriedMore ? redacted + "/…" : redacted
    }

    /// Matches `scheme://…` up to the first whitespace. Deliberately greedy on
    /// the tail: a path or query is exactly what has to be removed, so it must
    /// be inside the match.
    private static let urlDetector: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "[a-zA-Z][a-zA-Z0-9+.-]*://[^\\s\"']+")
    }()
}
