//
//  SwapTokenTrust.swift
//  VultisigApp
//
//  Recents and the unverified-token check for the reworked token picker.
//
//  A token is unverified when it claims the ticker of a curated token on the
//  same chain but sits at a different contract: the classic impersonation.
//  Picking one needs an explicit acknowledgment; the sheet offers the real
//  token instead.
//

import Foundation

enum SwapTokenTrust: Equatable {
    case verified
    /// `genuineContract` is the curated token the ticker belongs to.
    case unverified(genuineContract: String)

    struct Token: Equatable {
        let chain: String
        let ticker: String
        /// Empty for a chain's native coin.
        let contract: String
    }

    /// `genuineContract` is empty when the ticker belongs to the chain's
    /// native coin (an ERC-20 called "ETH" impersonating ether).
    static func assess(_ token: Token, curated: [Token]) -> SwapTokenTrust {
        guard !token.contract.isEmpty else { return .verified }
        let sameTicker = curated.filter {
            $0.chain == token.chain && $0.ticker.caseInsensitiveCompare(token.ticker) == .orderedSame
        }
        guard let first = sameTicker.first else { return .verified }
        if sameTicker.contains(where: { sameContract($0.contract, token.contract) }) {
            return .verified
        }
        let genuine = sameTicker.first(where: { !$0.contract.isEmpty }) ?? first
        return .unverified(genuineContract: genuine.contract)
    }

    /// Hex (EVM-style) addresses are case-insensitive; base58 mints and other
    /// encodings are not, so only a "0x" pair compares ignoring case.
    static func sameContract(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs.hasPrefix("0x") && rhs.hasPrefix("0x") {
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
        return lhs == rhs
    }

    /// "0x9f3a…c41b"
    static func shortContract(_ contract: String) -> String {
        guard !contract.isEmpty else { return "swapReworkNativeCoin".localized }
        guard contract.count > 12 else { return contract }
        return "\(contract.prefix(6))…\(contract.suffix(4))"
    }
}

/// The last tokens picked in the swap form, most recent first, shared by both
/// sides. Ids are `Coin.id` strings.
struct SwapRecentTokens {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    init(defaults: UserDefaults = .standard, key: String = "swapReworkRecentTokens", limit: Int = SwapReworkConfig.recentTokensLimit) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    var ids: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func record(_ id: String) {
        defaults.set(Self.merged(ids, adding: id, limit: limit), forKey: key)
    }

    static func merged(_ ids: [String], adding id: String, limit: Int) -> [String] {
        Array(([id] + ids.filter { $0 != id }).prefix(limit))
    }
}
