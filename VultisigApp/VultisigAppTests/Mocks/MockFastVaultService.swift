//
//  MockFastVaultService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await

final class MockFastVaultService: FastVaultServiceProtocol {
    var stubbedExist: Bool = false
    private(set) var existCallCount = 0
    private(set) var lastQueriedPubKey: String?

    func exist(pubKeyECDSA: String) async -> Bool {
        existCallCount += 1
        lastQueriedPubKey = pubKeyECDSA
        return stubbedExist
    }
}

// swiftlint:enable async_without_await
