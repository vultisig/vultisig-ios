//
//  MockTHORChainStakingService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable unused_parameter async_without_await

/// Returns a fixed staking snapshot so the THORChain staking branches can be
/// driven without the network.
struct MockTHORChainStakingService: THORChainStakingProviding {
    let details: StakingDetails

    func fetchStakingDetails(coinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String) async throws -> StakingDetails {
        details
    }
}

/// Fails every read, so callers can be checked for keeping the last known
/// position rather than reporting a zero.
struct FailingTHORChainStakingService: THORChainStakingProviding {
    func fetchStakingDetails(coinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String) async throws -> StakingDetails {
        throw StakingError.invalidResponse
    }
}

// swiftlint:enable unused_parameter async_without_await
