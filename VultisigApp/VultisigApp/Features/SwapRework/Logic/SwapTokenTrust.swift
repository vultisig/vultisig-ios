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

    static func assess(_ token: Token, curated: [Token]) -> SwapTokenTrust {
        guard !token.contract.isEmpty else { return .verified }
        let sameTicker = curated.filter {
            $0.chain == token.chain && $0.ticker.caseInsensitiveCompare(token.ticker) == .orderedSame
        }
        guard !sameTicker.isEmpty else { return .verified }
        if sameTicker.contains(where: { $0.contract.caseInsensitiveCompare(token.contract) == .orderedSame }) {
            return .verified
        }
        guard let genuine = sameTicker.first(where: { !$0.contract.isEmpty }) else { return .verified }
        return .unverified(genuineContract: genuine.contract)
    }

    /// "0x9f3a…c41b"
    static func shortContract(_ contract: String) -> String {
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
