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
    /// vs `Maya Protocol`), and sub-provider suffixes (`SwapKit (Chainflip)`) —
    /// so matching is case-insensitive substring, not exact equality. An
    /// empty/absent or unrecognised name yields `nil`.
    init?(persistedName raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        // SwapKit is checked first: its sub-provider strings carry the underlying
        // protocol in parentheses (e.g. "SwapKit (THORChain)"), and the outer
        // brand is what we render. Markers are the full brand token, not a loose
        // prefix — `thorchain` not `thor` (which is a substring of "Author"), and
        // `li.fi` with the dot not `lifi` (a substring of "amplifier").
        if normalized.contains("swapkit") {
            self = .swapkit
        } else if normalized.contains("thorchain") {
            self = .thorchain
        } else if normalized.contains("maya") {
            self = .maya
        } else if normalized.contains("1inch") {
            self = .oneInch
        } else if normalized.contains("kyber") {
            self = .kyberSwap
        } else if normalized.contains("li.fi") {
            self = .lifi
        } else if normalized.contains("jupiter") {
            self = .jupiter
        } else {
            return nil
        }
    }
}
