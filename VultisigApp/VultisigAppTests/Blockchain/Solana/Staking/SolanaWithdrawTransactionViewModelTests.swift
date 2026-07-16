//
//  SolanaWithdrawTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the TRUE full-withdraw contract: the withdrawable amount is the stake
//  account's ENTIRE balance (delegated stake + auto-compounded rewards + the
//  rent-exempt reserve), not stake-minus-reserve. Draining a fully-inactive
//  account to 0 lamports closes it on-chain and refunds the reserve; subtracting
//  it would strand dust in a 0-stake account the network no longer tracks. Also
//  checks the full balance survives the builder's lamports→decimal→lamports
//  round-trip so the signed withdraw closes the account exactly.
//

@testable import VultisigApp
import XCTest

// Protocol conformance forces `async throws` this fake never awaits, and the
// withdraw VM never invokes these reads in the paths under test.
// swiftlint:disable async_without_await unused_parameter
private final class FakeWithdrawStakingService: SolanaStakingServiceProtocol, @unchecked Sendable {
    func fetchValidators() async throws -> [SolanaValidator] { [] }
    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] { [] }
    func fetchStakeAccount(address: String) async throws -> SolanaStakeAccount? { nil }
    func fetchEpochInfo() async throws -> SolanaEpochInfo {
        SolanaEpochInfo(epoch: 800, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1)
    }
    func fetchRentReserve() async throws -> UInt64 { 2_282_880 }
    func fetchMinDelegation() async throws -> UInt64 { 1_000_000_000 }
    func fetchInflationRate() async throws -> Double { 0.07 }
}
// swiftlint:enable async_without_await unused_parameter

@MainActor
final class SolanaWithdrawTransactionViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!

    private let stake: UInt64 = 1_000_000_000
    private let reserve: UInt64 = 2_282_880

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

    private func stakeAccount() -> SolanaStakeAccount {
        SolanaStakeAccount(
            pubkey: "Stake11111111111111111111111111111111111111",
            lamports: stake + reserve,
            rentExemptReserve: reserve,
            staker: "Owner",
            withdrawer: "Owner",
            delegation: nil
        )
    }

    private func makeViewModel() -> SolanaWithdrawTransactionViewModel {
        SolanaWithdrawTransactionViewModel(
            coin: solCoin(),
            vault: vault,
            stakeAccount: stakeAccount(),
            stakingService: FakeWithdrawStakingService()
        )
    }

    func testWithdrawableLamportsIsFullBalanceIncludingRentReserve() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.withdrawableLamports, stake + reserve)
        XCTAssertNotEqual(vm.withdrawableLamports, stake, "must not strand the rent-exempt reserve")
    }

    func testBuilderForwardsFullBalanceLamports() throws {
        let vm = makeViewModel()
        let builder = SolanaWithdrawTransactionBuilder(
            coin: solCoin(),
            stakeAccount: stakeAccount().pubkey,
            amount: vm.withdrawableAmount.formatToDecimal(digits: vm.coin.decimals)
        )
        let payload = try XCTUnwrap(builder.solanaStakingPayload)
        XCTAssertEqual(payload.opType, .withdraw)
        XCTAssertEqual(payload.lamports, stake + reserve, "the full balance must close the account exactly")
    }
}
