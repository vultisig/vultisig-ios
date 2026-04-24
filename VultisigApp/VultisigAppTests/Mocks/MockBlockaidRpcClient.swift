//
//  MockBlockaidRpcClient.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable unused_parameter async_without_await

/// Test-only `BlockaidRpcClientProtocol` double that records `simulateEVMTransaction`
/// call counts and returns whatever `Result` the test configures.
///
/// Other RPC methods are not exercised by simulation tests and throw to surface
/// accidental usage.
final class MockBlockaidRpcClient: BlockaidRpcClientProtocol {

    enum StubError: Error {
        case notStubbed
        case simulated
    }

    var simulateResult: Result<BlockaidEvmSimulationResponseJson, Error> = .failure(StubError.notStubbed)
    private(set) var simulateCallCount = 0
    private(set) var simulatedMemos: [String] = []

    var simulateSolanaResult: Result<BlockaidSolanaSimulationResponseJson, Error> = .failure(StubError.notStubbed)
    private(set) var simulateSolanaCallCount = 0
    private(set) var simulatedSolanaRawTransactions: [[String]] = []

    func simulateEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidEvmSimulationResponseJson {
        simulateCallCount += 1
        simulatedMemos.append(data)
        return try simulateResult.get()
    }

    func simulateSolanaTransaction(
        address: String,
        rawTransactions: [String]
    ) async throws -> BlockaidSolanaSimulationResponseJson {
        simulateSolanaCallCount += 1
        simulatedSolanaRawTransactions.append(rawTransactions)
        return try simulateSolanaResult.get()
    }

    func scanEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        throw StubError.notStubbed
    }

    func scanBitcoinTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        throw StubError.notStubbed
    }

    func scanSolanaTransaction(
        address: String,
        serializedMessage: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        throw StubError.notStubbed
    }

    func scanSuiTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        throw StubError.notStubbed
    }
}
// swiftlint:enable unused_parameter async_without_await
