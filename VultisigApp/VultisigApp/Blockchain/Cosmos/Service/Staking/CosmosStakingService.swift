//
//  CosmosStakingService.swift
//  VultisigApp
//
//  Read-side service for Cosmos-SDK x/staking + x/distribution LCD
//  endpoints. Goes through the shared `HTTPClient` per the networking
//  rule — view-models call only the service.
//
//  Mirrors the SDK consumer at
//  `vultisig-sdk/packages/core/chain/chains/cosmos/staking/lcdQueries.ts`.
//

import Foundation
import OSLog

protocol CosmosStakingServiceProtocol {
    func fetchDelegations(chain: Chain, address: String) async throws -> [CosmosDelegation]
    func fetchUnbondingDelegations(chain: Chain, address: String) async throws -> [CosmosUnbondingDelegation]
    func fetchDelegatorRewards(chain: Chain, address: String) async throws -> CosmosDelegatorRewards
    func fetchValidators(chain: Chain) async throws -> [CosmosValidator]
    func fetchRedelegations(chain: Chain, address: String) async throws -> [CosmosRedelegationEntry]
}

struct CosmosStakingService: CosmosStakingServiceProtocol {

    private let httpClient: HTTPClientProtocol
    private let logger: Logger

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-staking-service")
    ) {
        self.httpClient = httpClient
        self.logger = logger
    }

    func fetchDelegations(chain: Chain, address: String) async throws -> [CosmosDelegation] {
        let baseURL = try Self.baseURL(for: chain)
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .delegations(address: address)),
            responseType: CosmosDelegationResponse.self
        )
        return response.data.toDelegations()
    }

    func fetchUnbondingDelegations(chain: Chain, address: String) async throws -> [CosmosUnbondingDelegation] {
        let baseURL = try Self.baseURL(for: chain)
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .unbondingDelegations(address: address)),
            responseType: CosmosUnbondingDelegationResponse.self
        )
        return response.data.toUnbondingDelegations()
    }

    func fetchDelegatorRewards(chain: Chain, address: String) async throws -> CosmosDelegatorRewards {
        let baseURL = try Self.baseURL(for: chain)
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .delegatorRewards(address: address)),
            responseType: CosmosDelegatorRewardsResponse.self
        )
        return response.data.toRewards()
    }

    func fetchValidators(chain: Chain) async throws -> [CosmosValidator] {
        let baseURL = try Self.baseURL(for: chain)
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .bondedValidators),
            responseType: CosmosValidatorListResponse.self
        )
        return response.data.toValidators()
    }

    func fetchRedelegations(chain: Chain, address: String) async throws -> [CosmosRedelegationEntry] {
        let baseURL = try Self.baseURL(for: chain)
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .redelegations(address: address)),
            responseType: CosmosRedelegationResponse.self
        )
        return response.data.toRedelegations()
    }

    // MARK: - Per-chain base URL

    /// Resolves the LCD host for the chain by going through
    /// `CosmosServiceConfig` — that's the single source of truth for every
    /// Cosmos REST root in the app (Terra and TerraClassic are wired direct
    /// to publicnode there). Keeping the lookup centralized means swapping
    /// to the api.vultisig.com proxy later is a one-line edit.
    private static func baseURL(for chain: Chain) throws -> URL {
        let config = try CosmosServiceConfig.getConfig(forChain: chain)
        guard let url = config.baseURL else {
            throw CosmosStakingConfigError.unsupportedChain(chain)
        }
        return url
    }
}
