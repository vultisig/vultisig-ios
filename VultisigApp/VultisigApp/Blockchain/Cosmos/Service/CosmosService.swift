//
//  CosmosService.swift
//  VultisigApp
//
//  Refactored to use enum (value type) instead of classes
//

import Foundation

enum CosmosService {
    case gaiaChain
    case dydx
    case kujira
    case osmosis
    case terra
    case terraClassic
    case noble
    case akash
    case qbtc

    // MARK: - Factory Methods

    /// Get Cosmos service for a chain - returns enum (value type)
    static func getService(forChain chain: Chain) throws -> CosmosService {
        return try forChain(chain)
    }

    /// Alternative factory method
    static func forChain(_ chain: Chain) throws -> CosmosService {
        switch chain {
        case .gaiaChain:
            return .gaiaChain
        case .dydx:
            return .dydx
        case .kujira:
            return .kujira
        case .osmosis:
            return .osmosis
        case .terra:
            return .terra
        case .terraClassic:
            return .terraClassic
        case .noble:
            return .noble
        case .akash:
            return .akash
        case .qbtc:
            return .qbtc
        default:
            throw CosmosServiceError.unsupportedChain
        }
    }

    // MARK: - Configuration

    var chain: Chain {
        switch self {
        case .gaiaChain:
            return .gaiaChain
        case .dydx:
            return .dydx
        case .kujira:
            return .kujira
        case .osmosis:
            return .osmosis
        case .terra:
            return .terra
        case .terraClassic:
            return .terraClassic
        case .noble:
            return .noble
        case .akash:
            return .akash
        case .qbtc:
            return .qbtc
        }
    }

    // MARK: - Service Implementation

    private var service: CosmosServiceStruct {
        let config = CosmosServiceConfig(chain: chain)
        return CosmosServiceStruct(config: config)
    }

    // MARK: - Public API

    func fetchBalances(coin: CoinMeta, address: String) async throws -> [CosmosBalance] {
        return try await service.fetchBalances(coin: coin, address: address)
    }

    func fetchIbcDenomTraces(coin: Coin) async -> CosmosIbcDenomTraceDenomTrace? {
        return await service.fetchIbcDenomTraces(coin: coin)
    }

    func fetchWasmTokenBalances(coin: Coin) async throws -> String {
        return try await service.fetchWasmTokenBalances(coin: coin.toCoinMeta(), address: coin.address)
    }

    func fetchLatestBlock() async throws -> String {
        return try await service.fetchLatestBlock()
    }

    func fetchAccountNumber(_ address: String) async throws -> CosmosAccountValue? {
        return try await service.fetchAccountNumber(address)
    }

    /// Terra Classic's live proportional burn-tax rate (`x/tax` module). Returns
    /// a conservative fallback on failure (fails closed).
    func fetchTerraClassicBurnTaxRate() async -> Decimal {
        return await service.fetchTerraClassicBurnTaxRate()
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        return await service.broadcastTransaction(jsonString: jsonString)
    }

    /// Estimate gas via `/cosmos/tx/v1beta1/simulate`. `txBytes` is a base64
    /// protobuf `TxRaw` with a dummy signature. Returns the node's reported
    /// `gas_used`; throws on failure so the caller can fall back to static gas.
    func simulateGas(txBytes: String) async throws -> UInt64 {
        return try await service.simulateGas(txBytes: txBytes)
    }
}
