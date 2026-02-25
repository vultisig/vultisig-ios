//
//  THORChainSwapPayload.swift
//  VultisigApp
//

import Foundation
import WalletCore
import BigInt

extension THORChainSwapChain: @retroactive Codable {}

extension THORChainSwapAsset: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case chain
        case symbol
        case tokenID
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chain = try container.decode(THORChainSwapChain.self, forKey: .chain)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.tokenID = try container.decode(String.self, forKey: .tokenID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.chain, forKey: .chain)
        try container.encode(self.symbol, forKey: .symbol)
        try container.encode(self.tokenID, forKey: .tokenID)
    }
}

struct THORChainSwapPayload: Codable, Hashable {
    let fromAddress: String
    let fromCoin: Coin
    let toCoin: Coin
    let vaultAddress: String
    let routerAddress: String?
    let fromAmount: BigInt // fromCoin raw amount
    let toAmountDecimal: Decimal // toCoin decimal amount
    let toAmountLimit: String
    let streamingInterval: String
    let streamingQuantity: String
    let expirationTime: UInt64
    let isAffiliate: Bool

    var toAddress: String {
        return toCoin.address
    }

    var fromAsset: THORChainSwapAsset {
        return swapAsset(for: fromCoin, source: true)
    }

    var toAsset: THORChainSwapAsset {
        return swapAsset(for: toCoin, source: false)
    }
}

private extension THORChainSwapPayload {

    func swapAsset(for coin: Coin, source: Bool) -> THORChainSwapAsset {
        return THORChainSwapAsset.with {
            switch coin.chain {
            case .thorChain, .thorChainChainnet, .thorChainStagenet:
                $0.chain = .thor
            case .ethereum:
                $0.chain = .eth
            case .avalanche:
                $0.chain = .avax
            case .bscChain:
                $0.chain = .bsc
            case .bitcoin:
                $0.chain = .btc
            case .bitcoinCash:
                $0.chain = .bch
            case .litecoin:
                $0.chain = .ltc
            case .dogecoin:
                $0.chain = .doge
            case .gaiaChain:
                $0.chain = .atom
            case .solana, .sui, .dash, .kujira, .mayaChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .polkadot, .zksync, .dydx, .ton, .osmosis, .terra, .terraClassic, .noble, .ripple, .akash, .tron, .ethereumSepolia, .zcash, .cardano, .mantle, .hyperliquid, .sei: break
            }

            $0.symbol = coin.ticker

            if !coin.isNativeToken {
                if source {
                    $0.tokenID = coin.contractAddress
                } else {
                    $0.tokenID = "\(coin.ticker)-\(coin.contractAddress.suffix(6).uppercased())"
                }
            }
        }
    }
}
