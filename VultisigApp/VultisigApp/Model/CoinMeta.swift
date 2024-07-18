//
//  CoinMeta.swift
//  VultisigApp
//
//  Created by Johnny Luo on 20/6/2024.
//

import Foundation
import WalletCore

class CoinMeta : Hashable, Codable {
    let chain: Chain
    let ticker: String
    let logo: String
    let decimals: Int
    let contractAddress: String
    let isNativeToken: Bool
    let priceProviderId: String
    
    init(
        chain: Chain,
        ticker: String,
        logo: String,
        decimals: Int,
        priceProviderId: String,
        contractAddress: String,
        isNativeToken: Bool
    ) {
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
        return "\(chain.rawValue)-\(ticker)-\(address)"
    }
    
    static var example = CoinMeta(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 1, priceProviderId: "provider", contractAddress: "123456789", isNativeToken: true)
    
    // Hashable conformance
    static func == (lhs: CoinMeta, rhs: CoinMeta) -> Bool {
        return lhs.chain == rhs.chain &&
            lhs.ticker == rhs.ticker &&
            lhs.logo == rhs.logo &&
            lhs.decimals == rhs.decimals &&
            lhs.contractAddress == rhs.contractAddress &&
            lhs.isNativeToken == rhs.isNativeToken &&
            lhs.priceProviderId == rhs.priceProviderId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chain)
        hasher.combine(ticker)
        hasher.combine(logo)
        hasher.combine(decimals)
        hasher.combine(contractAddress)
        hasher.combine(isNativeToken)
        hasher.combine(priceProviderId)
    }

    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case chain, ticker, logo, decimals, contractAddress, isNativeToken, priceProviderId
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chain = try container.decode(Chain.self, forKey: .chain)
        ticker = try container.decode(String.self, forKey: .ticker)
        logo = try container.decode(String.self, forKey: .logo)
        decimals = try container.decode(Int.self, forKey: .decimals)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        isNativeToken = try container.decode(Bool.self, forKey: .isNativeToken)
        priceProviderId = try container.decode(String.self, forKey: .priceProviderId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(logo, forKey: .logo)
        try container.encode(decimals, forKey: .decimals)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(isNativeToken, forKey: .isNativeToken)
        try container.encode(priceProviderId, forKey: .priceProviderId)
    }
}

