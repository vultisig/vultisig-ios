//
//  CoinMeta.swift
//  VultisigApp
//
//  Created by Johnny Luo on 20/6/2024.
//

import Foundation
import WalletCore

struct CoinMeta: Hashable, Codable {
    let chain: Chain
    let ticker: String
    var logo: String
    let decimals: Int
    let contractAddress: String
    let isNativeToken: Bool
    var priceProviderId: String

    init(chain: Chain,
         ticker: String,
         logo: String,
         decimals: Int,
         priceProviderId: String,
         contractAddress: String,
         isNativeToken: Bool) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.decimals = decimals
        self.contractAddress = contractAddress
        self.isNativeToken = isNativeToken
        self.priceProviderId = priceProviderId
    }

    var tokenChainLogo: String? {
        guard !isNativeToken else { return nil }
        return chain.logo
    }

    var coinType: CoinType {
        return self.chain.coinType
    }

    func coinId(address: String) -> String {
        return "\(chain.rawValue)-\(ticker)-\(address)-\(contractAddress)"
    }

    static var example = CoinMeta(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 1, priceProviderId: "provider", contractAddress: "123456789", isNativeToken: true)

    private var normalizedTicker: String {
        ticker.lowercased()
    }

    private var normalizedContract: String {
        contractAddress.lowercased()
    }

    var uniqueId: String {
        "\(chain.rawValue)-\(normalizedTicker)-\(normalizedContract)"
    }
}

extension CoinMeta {

    /// Tickers that name a DeFi *position* rather than a spendable wallet token.
    ///
    /// These are receipts a staking contract mints — sTCY for staked TCY,
    /// ybRUNE (`x/staking-x/brune`) for bonded bRUNE. A vault legitimately holds
    /// them (THORChain discovery adds whatever denoms the address carries, and
    /// the DeFi cards read the held coin), so this is not about whether the coin
    /// exists — it is about which surfaces may offer one as an ordinary token.
    /// They are excluded from the wallet token list, the token-selection sheet,
    /// the swap picker's held tokens and the vault's fiat total; they are
    /// enabled and unwound through the DeFi position picker instead, which
    /// sources its own list from `TokensStore` rather than the token catalog.
    ///
    /// Lives on `CoinMeta` because the selection surfaces are `CoinMeta`-typed
    /// throughout — `Coin.isDefiOnly` forwards here so both sides can never
    /// disagree about what counts.
    static let defiOnlyTickers: Set<String> = ["STCY", "YBRUNE"]

    var isDefiOnly: Bool {
        CoinMeta.defiOnlyTickers.contains(ticker.uppercased())
    }
}

extension CoinMeta: Equatable {
    static func == (lhs: CoinMeta, rhs: CoinMeta) -> Bool {
        return lhs.chain == rhs.chain &&
        lhs.normalizedTicker == rhs.normalizedTicker &&
        lhs.normalizedContract == rhs.normalizedContract
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chain)
        hasher.combine(normalizedTicker)
        hasher.combine(normalizedContract)
    }
}
