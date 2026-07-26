//
//  SwapProviderKind.swift
//  VultisigApp
//

import Foundation

/// Payload-free canonical identity of a swap provider, and the single source of
/// truth for its brand **logo** and **display name**.
///
/// Both the live swap flow (`SwapQuote`) and persisted Transaction History read
/// their provider logo/name from here, so the two can never drift. This is pure
/// presentation — it carries no quote payload and takes no part in Codable,
/// signing, or wire formats.
enum SwapProviderKind: Equatable {
    case thorchain
    case maya
    case oneInch
    case kyberSwap
    case lifi
    case swapkit
    case jupiter

    /// Brand-logo imageset name (in `Crypto/`), matching the imageset filenames.
    /// kyberswap/swapkit/jupiter have no bundled asset on purpose, so
    /// `AsyncImageView` falls back to a monogram built from the ticker.
    var providerLogo: String {
        switch self {
        case .thorchain:
            return "THORChain"
        case .maya:
            return "Maya protocol"
        case .oneInch:
            return "1Inch"
        case .lifi:
            return "LI.FI"
        case .kyberSwap:
            return "kyberswap"
        case .swapkit:
            return "swapkit"
        case .jupiter:
            return "jupiter"
        }
    }

    /// Canonical brand display name — coarse, with no network-variant suffix.
    /// (`SwapQuote.displayName` appends `-Chainnet`/`-Stagenet` for THORChain
    /// network variants on top of this.)
    var displayName: String {
        switch self {
        case .thorchain:
            return "THORChain"
        case .maya:
            return "Maya protocol"
        case .oneInch:
            return "1Inch"
        case .kyberSwap:
            return "KyberSwap"
        case .lifi:
            return "LI.FI"
        case .swapkit:
            return "SwapKit"
        case .jupiter:
            return "Jupiter"
        }
    }

    /// Resolves a **persisted** provider display string back to its kind.
    ///
    /// Transaction History stores only the display name, and it varies by record
    /// path — network suffixes (`THORChain-Stagenet`), casing (`Maya protocol`
    /// vs `Maya Protocol`), and sub-provider suffixes (`SwapKit (Chainflip)`).
    /// Persisted names are always `<Brand>` plus an optional SEPARATED qualifier,
    /// so we match the brand as a prefix whose following character (if any) is a
    /// non-alphanumeric boundary. That way real suffix forms resolve while
    /// near-matches (`SwapKitty`, `not-thorchain`, `mayachain`) fall through to
    /// `nil` and get the monogram fallback. An empty/absent or unrecognised name
    /// yields `nil`.
    init?(persistedName raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        // SwapKit is first so a sub-provider string that names its underlying
        // protocol (e.g. "SwapKit (THORChain)") resolves to the outer SwapKit
        // brand, not the inner protocol.
        let tokens: [(String, SwapProviderKind)] = [
            ("swapkit", .swapkit),
            ("thorchain", .thorchain),
            ("maya", .maya),
            ("1inch", .oneInch),
            ("kyberswap", .kyberSwap),
            ("li.fi", .lifi),
            ("jupiter", .jupiter)
        ]

        for (token, kind) in tokens where normalized.hasPrefix(token) {
            let next = normalized.dropFirst(token.count).first
            let isBoundary = next.map { !($0.isLetter || $0.isNumber) } ?? true
            if isBoundary {
                self = kind
                return
            }
        }

        return nil
    }
}
