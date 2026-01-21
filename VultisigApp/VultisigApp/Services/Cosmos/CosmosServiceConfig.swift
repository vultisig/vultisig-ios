//
//  CosmosServiceConfig.swift
//  VultisigApp
//
//  Value type configuration for Cosmos services
//

import Foundation

struct CosmosServiceConfig {
    let chain: Chain
    
    // URL builders
    func balanceURL(forAddress address: String) -> URL? {
        return URL(string: balanceURLString(forAddress: address))
    }
    
    func accountNumberURL(forAddress address: String) -> URL? {
        return URL(string: accountNumberURLString(forAddress: address))
    }
    
    func transactionURL() -> URL? {
        return URL(string: transactionURLString())
    }
    
    func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        return URL(string: wasmTokenBalanceURLString(contractAddress: contractAddress, base64Payload: base64Payload))
    }
    
    func ibcDenomTraceURL(hash: String) -> URL? {
        return URL(string: ibcDenomTraceURLString(hash: hash))
    }
    
    func latestBlockURL() -> URL? {
        return URL(string: latestBlockURLString())
    }
    
    // Private URL string builders
    private func balanceURLString(forAddress address: String) -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.fetchCosmosAccountBalance(address: address)
        case .dydx:
            return Endpoint.fetchDydxAccountBalance(address: address)
        case .kujira:
            return Endpoint.fetchKujiraAccountBalance(address: address)
        case .osmosis:
            return Endpoint.fetchOsmosisAccountBalance(address: address)
        case .terra:
            return Endpoint.fetchTerraAccountBalance(address: address)
        case .terraClassic:
            return Endpoint.fetchTerraClassicAccountBalance(address: address)
        case .noble:
            return Endpoint.fetchNobleAccountBalance(address: address)
        case .akash:
            return Endpoint.fetchAkashAccountBalance(address: address)
        default:
            return ""
        }
    }
    
    private func accountNumberURLString(forAddress address: String) -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.fetchCosmosAccountNumber(address)
        case .dydx:
            return Endpoint.fetchDydxAccountNumber(address)
        case .kujira:
            return Endpoint.fetchKujiraAccountNumber(address)
        case .osmosis:
            return Endpoint.fetchOsmosisAccountNumber(address)
        case .terra:
            return Endpoint.fetchTerraAccountNumber(address)
        case .terraClassic:
            return Endpoint.fetchTerraClassicAccountNumber(address)
        case .noble:
            return Endpoint.fetchNobleAccountNumber(address)
        case .akash:
            return Endpoint.fetchAkashAccountNumber(address)
        default:
            return ""
        }
    }
    
    private func transactionURLString() -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.broadcastCosmosTransaction
        case .dydx:
            return Endpoint.broadcastDydxTransaction
        case .kujira:
            return Endpoint.broadcastKujiraTransaction
        case .osmosis:
            return Endpoint.broadcastOsmosisTransaction
        case .terra:
            return Endpoint.broadcastTerraTransaction
        case .terraClassic:
            return Endpoint.broadcastTerraClassicTransaction
        case .noble:
            return Endpoint.broadcastNobleTransaction
        case .akash:
            return Endpoint.broadcastAkashTransaction
        default:
            return ""
        }
    }
    
    private func wasmTokenBalanceURLString(contractAddress: String, base64Payload: String) -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.fetchCosmosWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload)
        case .kujira:
            return Endpoint.fetchKujiraWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload)
        case .osmosis:
            return Endpoint.fetchOsmosisWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload)
        case .terra:
            return Endpoint.fetchTerraWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload)
        case .terraClassic:
            return Endpoint.fetchTerraClassicWasmTokenBalance(contractAddress: contractAddress, base64Payload: base64Payload)
        default:
            return ""
        }
    }
    
    private func ibcDenomTraceURLString(hash: String) -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.fetchCosmosIbcDenomTraces(hash: hash)
        case .kujira:
            return Endpoint.fetchKujiraIbcDenomTraces(hash: hash)
        case .osmosis:
            return Endpoint.fetchOsmosisIbcDenomTraces(hash: hash)
        case .terra:
            return Endpoint.fetchTerraIbcDenomTraces(hash: hash)
        case .terraClassic:
            return Endpoint.fetchTerraClassicIbcDenomTraces(hash: hash)
        default:
            return ""
        }
    }
    
    private func latestBlockURLString() -> String {
        switch chain {
        case .gaiaChain:
            return Endpoint.fetchCosmosLatestBlock()
        case .kujira:
            return Endpoint.fetchKujiraLatestBlock()
        case .osmosis:
            return Endpoint.fetchOsmosisLatestBlock()
        case .terra:
            return Endpoint.fetchTerraLatestBlock()
        case .terraClassic:
            return Endpoint.fetchTerraClassicLatestBlock()
        default:
            return ""
        }
    }
    
    static func getConfig(forChain chain: Chain) throws -> CosmosServiceConfig {
        switch chain {
        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash:
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
