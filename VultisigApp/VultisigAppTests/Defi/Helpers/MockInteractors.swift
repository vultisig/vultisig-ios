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
    var error: Error?
    private(set) var callCount = 0

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        callCount += 1
        return stub
    }
}

final class MockLPsInteractor: LPsInteractor, @unchecked Sendable {
    var stub: [LPPositionData] = []
    var error: Error?
    private(set) var callCount = 0

    func fetchLPPositions(vault: Vault) async throws -> [LPPositionData] {
        callCount += 1
        if let error { throw error }
        return stub
    }
}

// swiftlint:enable async_without_await unused_parameter

enum MockInteractorError: Error, Equatable {
    case generic
}
