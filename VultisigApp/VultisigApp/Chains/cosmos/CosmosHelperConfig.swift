//
//  CosmosHelperConfig.swift
//  VultisigApp
//
//  Refactored to use struct (value type) instead of classes
//

import Foundation
import WalletCore

struct CosmosHelperConfig {
    let chain: Chain
    let coinType: CoinType
    let denom: String
    let gasLimit: UInt64
    
    static func getConfig(forChain chain: Chain) throws -> CosmosHelperConfig {
        switch chain {
        case .gaiaChain:
            return CosmosHelperConfig(chain: chain, coinType: .cosmos, denom: "uatom", gasLimit: 200000)
        case .kujira:
            return CosmosHelperConfig(chain: chain, coinType: .kujira, denom: "ukuji", gasLimit: 200000)
        case .osmosis:
            return CosmosHelperConfig(chain: chain, coinType: .osmosis, denom: "uosmo", gasLimit: 300000)
        case .noble:
            return CosmosHelperConfig(chain: chain, coinType: .noble, denom: "uusdc", gasLimit: 200000)
        case .akash:
            return CosmosHelperConfig(chain: chain, coinType: .akash, denom: "uakt", gasLimit: 200000)
        case .terra:
            return CosmosHelperConfig(chain: chain, coinType: .terraV2, denom: "uluna", gasLimit: 300000)
        case .terraClassic:
            return CosmosHelperConfig(chain: chain, coinType: .terra, denom: "uluna", gasLimit: 300000)
        case .dydx:
            return CosmosHelperConfig(chain: chain, coinType: .dydx, denom: "adydx", gasLimit: 200000)
        default:
            throw HelperError.runtimeError("Unsupported Cosmos chain: \(chain)")
        }
    }
}
