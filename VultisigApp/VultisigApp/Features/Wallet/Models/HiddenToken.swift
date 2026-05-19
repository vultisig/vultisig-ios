//
//  HiddenToken.swift
//  VultisigApp
//
//  Created by Assistant on 2024-01-03.
//

import Foundation
import SwiftData

@Model
class HiddenToken {
    var chain: String
    var ticker: String
    var contractAddress: String
    var hiddenAt: Date

    @Relationship(inverse: \Vault.hiddenTokens) var vault: Vault?

    init(chain: Chain, ticker: String, contractAddress: String) {
        self.chain = chain.rawValue
        self.ticker = ticker
        self.contractAddress = contractAddress
        self.hiddenAt = Date()
    }

    convenience init(coin: Coin) {
        self.init(chain: coin.chain, ticker: coin.ticker, contractAddress: coin.contractAddress)
    }

    /// Unique identifier for matching tokens
    var identifier: String {
        return "\(chain)-\(ticker)-\(contractAddress)"
    }

    private var normalizedTicker: String {
        ticker.lowercased()
    }

    private var normalizedContract: String {
        contractAddress.lowercased()
    }

    /// Maps a stale contract address recorded on existing hidden tokens to the
    /// current `TokensStore` value, so toggling the same asset off then on
    /// continues to match even when its contractAddress was rewritten.
    ///   - sTCY: chain moved `x/staking-x/tcy → x/staking-tcy` (PR #3837).
    ///   - sRUJI: PR #3837 also renamed sRUJI locally, but issue #4318 reverts
    ///            that — vaults that stored the renamed value need to match
    ///            the on-chain denom now used by `TokensStore.sruji`.
    private static let migratedContractAddresses: [String: String] = [
        "x/staking-x/tcy": "x/staking-tcy",
        "x/staking-ruji": TokensStore.sruji.contractAddress
    ]

    /// Check if this hidden token matches a CoinMeta
    func matches(_ coinMeta: CoinMeta) -> Bool {
        guard chain.caseInsensitiveCompare(coinMeta.chain.rawValue) == .orderedSame,
              normalizedTicker == coinMeta.ticker.lowercased() else {
            return false
        }

        // Exact contract address match
        if normalizedContract == coinMeta.contractAddress.lowercased() {
            return true
        }

        // Check if the hidden token has an old migrated contract address
        // that maps to the current contract address
        if let newAddress = Self.migratedContractAddresses[normalizedContract],
           newAddress.lowercased() == coinMeta.contractAddress.lowercased() {
            return true
        }

        return false
    }
}

extension HiddenToken: Hashable {
    static func == (lhs: HiddenToken, rhs: HiddenToken) -> Bool {
        return lhs.chain.caseInsensitiveCompare(rhs.chain) == .orderedSame &&
               lhs.normalizedTicker == rhs.normalizedTicker &&
               lhs.normalizedContract == rhs.normalizedContract
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chain.lowercased())
        hasher.combine(normalizedTicker)
        hasher.combine(normalizedContract)
    }
}
