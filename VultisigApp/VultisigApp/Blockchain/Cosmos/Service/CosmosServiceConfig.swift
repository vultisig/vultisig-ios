//
//  CosmosServiceConfig.swift
//  VultisigApp
//

import Foundation

struct CosmosServiceConfig {
    let chain: Chain

    /// REST host for this chain. All `/cosmos/*`, `/ibc/*`, `/cosmwasm/*`
    /// paths are appended to this by `CosmosAPI`.
    var baseURL: URL? {
        switch chain {
        case .gaiaChain:
            return URL(string: "https://cosmos-rest.publicnode.com")
        case .dydx:
            return URL(string: "https://dydx-rest.publicnode.com")
        case .kujira:
            return URL(string: "https://kujira-rest.publicnode.com")
        case .osmosis:
            return URL(string: "https://osmosis-rest.publicnode.com")
        case .terra:
            return URL(string: "https://terra-lcd.publicnode.com")
        case .terraClassic:
            return URL(string: "https://terra-classic-lcd.publicnode.com")
        case .noble:
            return URL(string: "https://noble-api.polkachu.com")
        case .akash:
            return URL(string: "https://akash-rest.publicnode.com")
        case .qbtc:
            return URL(string: "https://api.vultisig.com/qbtc-rpc")
        default:
            return nil
        }
    }

    /// Terra and Terra Classic expose balances under the
    /// `spendable_balances` REST path; every other chain uses `balances`.
    var usesSpendableBalances: Bool {
        switch chain {
        case .terra, .terraClassic:
            return true
        default:
            return false
        }
    }

    static func getConfig(forChain chain: Chain) throws -> CosmosServiceConfig {
        switch chain {
        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash, .qbtc:
            return CosmosServiceConfig(chain: chain)
        default:
            throw CosmosServiceError.unsupportedChain
        }
    }
}

enum CosmosServiceError: Error, LocalizedError {
    case unsupportedChain

    var errorDescription: String? {
        switch self {
        case .unsupportedChain:
            return "Unsupported Cosmos chain"
        }
    }
}
