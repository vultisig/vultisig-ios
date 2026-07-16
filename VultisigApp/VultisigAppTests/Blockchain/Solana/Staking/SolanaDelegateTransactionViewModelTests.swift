//
//  SolanaDelegateTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the dynamic minimum-delegation contract: the delegate form seeds the
//  documented 1 SOL floor, adopts the live getStakeMinimumDelegation value when
//  the fetch succeeds, and keeps the seeded floor when the fetch fails (the
//  Vultisig proxy blocks the method, so it is read off a public node that may be
//  unreachable).
//

@testable import VultisigApp
import XCTest

// Protocol conformance forces `async throws` signatures the fake doesn't await
// on the no-op reads.
// swiftlint:disable async_without_await unused_parameter
private final class FakeDelegateStakingService: SolanaStakingServiceProtocol, @unchecked Sendable {
    var minDelegation: UInt64 = 1_000_000_000
    var minDelegationError: Error?

    func fetchValidators() async throws -> [SolanaValidator] { [] }
    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] { [] }
    func fetchStakeAccount(address: String) async throws -> SolanaStakeAccount? { nil }
    func fetchEpochInfo() async throws -> SolanaEpochInfo {
        SolanaEpochInfo(epoch: 800, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1)
    }
    func fetchRentReserve() async throws -> UInt64 { 2_282_880 }
    func fetchMinDelegation() async throws -> UInt64 {
        if let minDelegationError { throw minDelegationError }
        return minDelegation
    }
    func fetchInflationRate() async throws -> Double { 0.07 }
}
// swiftlint:enable async_without_await unused_parameter

private enum FakeRPCError: Error { case unavailable }

@MainActor
final class SolanaDelegateTransactionViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func solCoin() -> Coin {
        let meta = CoinMeta(
            chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
            priceProviderId: "solana", contractAddress: "", isNativeToken: true
        )
        return Coin(asset: meta, address: "Owner", hexPublicKey: "00")
    }

    private func makeViewModel(
        service: SolanaStakingServiceProtocol
    ) -> SolanaDelegateTransactionViewModel {
        SolanaDelegateTransactionViewModel(
            coin: solCoin(),
            vault: vault,
            stakingService: service
        )
    }

    func testSeedsDocumentedFloorBeforeFetch() {
        let vm = makeViewModel(service: FakeDelegateStakingService())
        XCTAssertEqual(vm.minimumDelegationLamports, SolanaStakingConfig.minDelegationFloorLamports)
        XCTAssertEqual(vm.minimumDelegationDecimal, 1)
    }

    func testAdoptsLiveMinimumWhenFetchSucceeds() async {
        let service = FakeDelegateStakingService()
        service.minDelegation = 2_000_000_000 // 2 SOL — a hypothetical feature-gate bump
        let vm = makeViewModel(service: service)

        await vm.loadMinDelegation()

        XCTAssertEqual(vm.minimumDelegationLamports, 2_000_000_000)
        XCTAssertEqual(vm.minimumDelegationDecimal, 2)
    }

    func testKeepsSeededFloorWhenFetchFails() async {
        let service = FakeDelegateStakingService()
        service.minDelegationError = FakeRPCError.unavailable
        let vm = makeViewModel(service: service)

        await vm.loadMinDelegation()

        XCTAssertEqual(vm.minimumDelegationLamports, SolanaStakingConfig.minDelegationFloorLamports)
        XCTAssertEqual(vm.minimumDelegationDecimal, 1)
    }
}
