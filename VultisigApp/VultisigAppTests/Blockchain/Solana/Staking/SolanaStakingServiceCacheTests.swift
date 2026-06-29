//
//  SolanaStakingServiceCacheTests.swift
//  VultisigAppTests
//
//  Pins the actor-cache TTL behavior: validator set + inflation are cached
//  (10 min) and refetch after the TTL; stake accounts are never cached.
//

@testable import VultisigApp
import Foundation
import XCTest

private final class MovableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval

    init(start: TimeInterval) { self.seconds = start }

    var value: Date { lock.withLock { Date(timeIntervalSince1970: seconds) } }

    func advance(to seconds: TimeInterval) {
        lock.withLock { self.seconds = seconds }
    }
}

// Protocol conformance forces `async throws` signatures the fakes don't await.
// swiftlint:disable async_without_await unused_parameter
private final class CountingReader: SolanaStakingReading, @unchecked Sendable {
    private(set) var validatorCalls = 0
    private(set) var stakeAccountCalls = 0
    private(set) var inflationCalls = 0
    private let lock = NSLock()

    func fetchSolanaValidators() async throws -> [SolanaValidator] {
        lock.withLock { validatorCalls += 1 }
        return [SolanaValidator(
            votePubkey: "Vote1", nodePubkey: "Node1", activatedStake: 1,
            commission: 0, epochVoteAccount: true, isDelinquent: false
        )]
    }

    func fetchSolanaStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] {
        lock.withLock { stakeAccountCalls += 1 }
        return []
    }

    func fetchSolanaEpochInfo() async throws -> SolanaEpochInfo {
        SolanaEpochInfo(epoch: 993, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1)
    }

    func fetchSolanaRentReserve() async throws -> UInt64 { 2_282_880 }

    func fetchSolanaInflationRate() async throws -> Double {
        lock.withLock { inflationCalls += 1 }
        return 0.0377
    }
}
// swiftlint:enable async_without_await unused_parameter

final class SolanaStakingServiceCacheTests: XCTestCase {

    func testValidatorSetServedFromCacheWithinTTL() async throws {
        let reader = CountingReader()
        let service = SolanaStakingService(
            solanaService: reader,
            validatorTTL: 600,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = try await service.fetchValidators()
        _ = try await service.fetchValidators()
        XCTAssertEqual(reader.validatorCalls, 1)
    }

    func testValidatorSetRefetchesAfterTTL() async throws {
        let reader = CountingReader()
        let now = MovableClock(start: 0)
        let service = SolanaStakingService(
            solanaService: reader,
            validatorTTL: 600,
            clock: { now.value }
        )
        _ = try await service.fetchValidators()
        now.advance(to: 601) // past the 10-min TTL
        _ = try await service.fetchValidators()
        XCTAssertEqual(reader.validatorCalls, 2)
    }

    func testInflationCachedWithinTTL() async throws {
        let reader = CountingReader()
        let service = SolanaStakingService(
            solanaService: reader,
            inflationTTL: 600,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = try await service.fetchInflationRate()
        _ = try await service.fetchInflationRate()
        XCTAssertEqual(reader.inflationCalls, 1)
    }

    func testStakeAccountsNeverCached() async throws {
        let reader = CountingReader()
        let service = SolanaStakingService(
            solanaService: reader,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = try await service.fetchStakeAccounts(owner: "Owner")
        _ = try await service.fetchStakeAccounts(owner: "Owner")
        // Must hit RPC every time — a just-submitted stake/unstake and freshly
        // accrued rewards have to be visible immediately.
        XCTAssertEqual(reader.stakeAccountCalls, 2)
    }
}
