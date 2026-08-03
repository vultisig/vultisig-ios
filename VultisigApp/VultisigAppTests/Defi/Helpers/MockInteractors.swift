//
//  MockInteractors.swift
//  VultisigAppTests
//
//  Test doubles for the Defi interactor protocols.
//

import Foundation
@testable import VultisigApp

// Mocks intentionally don't `await` and don't read `vault` — the signatures must match the
// production protocols exactly, so we can't rename the parameter or drop `async`.

// swiftlint:disable async_without_await unused_parameter

final class MockStakeInteractor: StakeInteractor, @unchecked Sendable {
    var stub: [StakePositionData] = []
    private(set) var callCount = 0

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        callCount += 1
        return stub
    }
}

final class MockLPsInteractor: LPsInteractor, @unchecked Sendable {
    var stub: [LPPositionData] = []
    private(set) var callCount = 0

    func fetchLPPositions(vault: Vault) async -> [LPPositionData] {
        callCount += 1
        return stub
    }
}

/// Test double for the selectable-position catalog. `lpDelay` and `lpError` let
/// a test hold the pool fetch open, fail it, or make it outlive the view model's
/// wall-clock budget — the three cases that used to blank the whole picker.
final class MockDefiPositionsProvider: DefiPositionsProviding, @unchecked Sendable {
    enum StubError: Error {
        case unreachable
    }

    var bondStub: [CoinMeta] = []
    var stakeStub: [CoinMeta] = []
    var lpStub: [CoinMeta] = []
    var supportsLPs = true
    var lpDelay: Duration?
    var lpError: Error?
    private(set) var lpCallCount = 0

    func bondCoins(for chain: Chain) -> [CoinMeta] { bondStub }

    func stakeCoins(for chain: Chain) -> [CoinMeta] { stakeStub }

    func supportsLiquidityPools(for chain: Chain) -> Bool { supportsLPs }

    func lpCoins(for chain: Chain) async throws -> [CoinMeta] {
        lpCallCount += 1
        if let lpDelay {
            try await Task.sleep(for: lpDelay)
        }
        if let lpError {
            throw lpError
        }
        return lpStub
    }
}

// swiftlint:enable async_without_await unused_parameter
