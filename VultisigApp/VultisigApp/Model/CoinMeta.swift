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
