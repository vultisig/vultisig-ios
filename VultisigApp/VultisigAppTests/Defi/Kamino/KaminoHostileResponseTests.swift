//
//  KaminoHostileResponseTests.swift
//  VultisigAppTests
//
//  `KaminoTransactionValidatorTests` proves the validator as a FUNCTION: given
//  these bytes and this intent, it refuses. That is the harder half of the
//  argument and it is thoroughly covered.
//
//  This suite proves the other half — that the function is actually in the path.
//  A validator that is never called, called with an intent derived from the same
//  response it is checking, or called on bytes the form then discards, passes
//  every test in that file and protects nothing. So these tests drive the REAL
//  `KaminoTransactionPreparer` through the REAL view models, with only the HTTP
//  response replaced, and assert that a tampered one produces no payload at all.
//
//  The control matters as much as the refusals: `testTheUntamperedResponseBuilds`
//  is what makes the rest meaningful. Without it a harness that refused
//  everything — a broken fixture, a mis-wired lookup table — would look like
//  perfect security.
//

import BigInt
@testable import VultisigApp
import SwiftData
import WalletCore
import XCTest

@MainActor
final class KaminoHostileResponseTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var service: HostileKaminoService!

    /// The vectors are single-signer transactions whose fee payer is this
    /// address, and the validator requires the payer to be the user — so the
    /// wallet coin has to carry it or every case would refuse for the wrong
    /// reason.
    private let owner = KaminoTransactionFixtures.usdcDeposit.feePayer

    /// The amount the captured deposit vector actually encodes. Requesting
    /// anything else is itself one of the tampering cases below.
    private static let vectorAmount = "10"

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        service = HostileKaminoService()
    }

    override func tearDown() async throws {
        service = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - The control

    /// The harness builds a payload when nothing is tampered with. Every refusal
    /// below is only evidence because this passes.
    func testTheUntamperedResponseBuilds() async throws {
        service.served = KaminoTransactionFixtures.usdcDeposit.source

        let handoff = await deposit(amount: Self.vectorAmount)

        let payload = try XCTUnwrap(handoff?.payload, "the untampered vector should build")
        guard case .signSolana(let solana)? = payload.signData else {
            return XCTFail("expected raw Solana bytes")
        }
        XCTAssertEqual(solana.rawTransactions.count, 1)

        // Coherence, which the byte-identity tests deliberately cannot assert:
        // they pair a sentinel's bytes with unrelated metadata precisely so the
        // hop is provable. Here everything came from one real preparation, so
        // the signed bytes, the compute budget the fee row reads and the marker
        // the verify screen cross-checks must all describe ONE transaction.
        let signed = try SolanaV0Transaction(base64Transaction: try XCTUnwrap(solana.rawTransactions.first))
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(signed),
            "the app must be able to read back what it just built"
        )
        guard case .Solana(let blockhash, let price, let limit, _, _, _) = payload.chainSpecific else {
            return XCTFail("expected Solana chain-specific data")
        }
        XCTAssertEqual(signed.recentBlockhash, blockhash)
        XCTAssertEqual(BigInt(try XCTUnwrap(decoded.priorityFee?.price)), price)
        XCTAssertEqual(BigInt(try XCTUnwrap(decoded.priorityFee?.limit)), limit)

        let marker = try XCTUnwrap(payload.kaminoPayload)
        XCTAssertEqual(decoded.operation, marker.operation)
        XCTAssertEqual(decoded.descriptor.address, marker.vaultAddress)
        XCTAssertEqual(String(decoded.amountBaseUnits), marker.amountBaseUnits)
        XCTAssertEqual(marker.amountBaseUnits, "10000000", "the vector deposits 10 USDC")
    }

    // MARK: - What a hostile response tries

    /// The response is for a different vault than the one the user chose. Funds
    /// would go somewhere real, and to a vault the app even curates — which is
    /// exactly why "it's a Kamino vault" is not the check.
    func testAResponseForADifferentVaultIsRefused() async {
        service.served = KaminoTransactionFixtures.solDeposit.source

        assertRefused(await deposit(amount: Self.vectorAmount))
    }

    /// The response performs the opposite operation. A withdraw dressed as a
    /// deposit would be approved on a screen that says "Deposit".
    ///
    /// The withdraw vector was captured from a different wallet, so served as-is
    /// it is refused at the fee payer before its instructions are read — which
    /// would leave the deposit-vs-withdraw check untested. The payer is
    /// therefore rewritten to the user first, so the refusal has to come from
    /// the operation itself.
    func testAResponseThatPerformsTheOtherOperationIsRefused() async throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        mutable.keys[0] = try Self.key(owner)
        service.served = try mutable.base64()

        assertRefused(await deposit(amount: Self.vectorAmount))
    }

    /// The response moves a different amount than was asked for. This is the
    /// check that cannot come from the response itself: the intent's amount is
    /// what the user typed, and the transaction has to answer it.
    func testAResponseCarryingADifferentAmountIsRefused() async {
        service.served = KaminoTransactionFixtures.usdcDeposit.source

        // The vector deposits 10 USDC; the user asked for 5.
        assertRefused(await deposit(amount: "5"))
    }

    /// The response arrives with a compute budget already in it. Before
    /// injection there is no legitimate ComputeBudget instruction — Kamino emits
    /// none — so one here is a priority fee the app did not choose, paid in SOL
    /// by the user, and unbounded.
    func testAResponseThatAlreadyCarriesAComputeBudgetIsRefused() async {
        service.served = KaminoTransactionFixtures.usdcDeposit.injected

        assertRefused(await deposit(amount: Self.vectorAmount))
    }

    /// The response carries a legitimate deposit AND a transfer to somewhere
    /// else. The deposit alone would decode and display correctly; what makes
    /// the transaction hostile is the instruction beside it.
    func testAResponseCarryingAnExtraTransferIsRefused() async throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let systemProgram = mutable.appendStaticReadonlyKey(try Self.key(Self.systemProgramId))
        let attacker = mutable.appendStaticReadonlyKey(try Self.key(Self.attackerAddress))
        mutable.instructions.append(
            .init(
                programIdIndex: systemProgram,
                // payer → attacker
                accounts: [0, attacker],
                data: Self.systemTransfer(lamports: 1_000_000_000)
            )
        )
        service.served = try mutable.base64()

        assertRefused(await deposit(amount: Self.vectorAmount))
    }

    /// The response is not a transaction this app can even read. It has to fail
    /// closed rather than reach a signer as an opaque blob.
    func testAnUnreadableResponseIsRefused() async {
        service.served = "not-base64-at-all"

        let handoff = await deposit(amount: Self.vectorAmount)
        XCTAssertNil(handoff?.payload, "an unparseable response must not produce a payload")
    }

    // MARK: - The withdraw path

    /// The withdraw control, and it is needed for the same reason as the deposit
    /// one: without it an always-refusing withdraw harness would look like a
    /// suite full of passing security assertions.
    ///
    /// The amount is chosen to convert to exactly the share count the captured
    /// vector burns — 5.794823 USDC is 5,500,000 shares at the fixture rate —
    /// because the validator pins that `u64` against the intent.
    func testTheUntamperedWithdrawBuilds() async throws {
        service.served = KaminoTransactionFixtures.usdcWithdraw.source
        service.lookupTable = KaminoTransactionFixtures.usdcWithdraw.lookupTable
        service.positions = [Self.position(unstaked: "10")]

        let viewModel = makeWithdrawViewModel(owner: KaminoTransactionFixtures.usdcWithdraw.feePayer)
        await viewModel.onLoad()
        viewModel.amountField.value = "5.794823"

        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made, "the untampered withdraw vector should build")

        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(5_500_000))
        guard case .signSolana(let solana)? = withdraw.payload.signData else {
            return XCTFail("expected raw Solana bytes")
        }
        XCTAssertEqual(solana.rawTransactions.count, 1)
    }

    /// The same wiring on the other flow, because it has its own view model and
    /// its own preparer entry point — a validator wired into one says nothing
    /// about the other.
    func testAWithdrawResponseForADifferentVaultIsRefused() async {
        service.served = KaminoTransactionFixtures.solDeposit.source
        service.positions = [Self.position(unstaked: "5.5")]

        let viewModel = makeWithdrawViewModel(owner: owner)
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        let withdraw = await viewModel.makeWithdraw()

        XCTAssertNil(withdraw, "a response for another vault must not produce a payload")
        XCTAssertTrue(
            Self.isRefusal(viewModel.error),
            "expected a refusal from the parser or the validator, got \(String(describing: viewModel.error))"
        )
    }

    // MARK: - Helpers

    /// The real pipeline: the real preparer, the real validator, fixture lookup
    /// tables, and a network that always agrees. Only the Kamino response is
    /// under the test's control.
    private func makePreparer() -> KaminoTransactionPreparer {
        KaminoTransactionPreparer(
            service: service,
            solana: PermissiveSolana(),
            validator: KaminoTransactionValidator(
                lookupTableSource: FixtureLookupTables()
            )
        )
    }

    private func makeWithdrawViewModel(owner: String) -> KaminoWithdrawViewModel {
        addCoin(address: owner)
        return KaminoWithdrawViewModel(
            vault: vault,
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            service: service,
            preparer: makePreparer()
        )
    }

    private static func position(unstaked: String) -> KaminoUserPositionResponse {
        KaminoUserPositionResponse(
            vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            stakedShares: "0",
            unstakedShares: unstaked,
            totalShares: unstaked
        )
    }

    private func deposit(amount: String) async -> KaminoDepositViewModel.DepositHandoff? {
        addCoin()
        let viewModel = KaminoDepositViewModel(
            vault: vault,
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            service: service,
            preparer: makePreparer(),
            balanceService: HostileBalanceService()
        )
        await viewModel.onLoad()
        viewModel.amountField.value = amount
        let handoff = await viewModel.makeDeposit()
        lastError = viewModel.error
        return handoff
    }

    private var lastError: Error?

    /// The claim is that **nothing signable is produced** and the form says why.
    ///
    /// Which layer catches it is deliberately not pinned: a hostile response can
    /// be refused by the byte parser (a fee payer that is not the user, a
    /// malformed message) or by the validator, and both are correct answers.
    /// Pinning the layer would make the test fail when a refusal moves *earlier*
    /// — the wrong direction to discourage. What is pinned is that the error is
    /// one of the app's own refusals rather than, say, a network failure that
    /// would have let a later retry through.
    private func assertRefused(
        _ handoff: KaminoDepositViewModel.DepositHandoff?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(handoff?.payload, "a tampered response must not produce a payload", file: file, line: line)
        XCTAssertTrue(
            Self.isRefusal(lastError),
            "expected a refusal from the parser or the validator, got \(String(describing: lastError))",
            file: file,
            line: line
        )
    }

    private static func isRefusal(_ error: Error?) -> Bool {
        error is KaminoValidationError || error is SolanaV0TransactionError
    }

    private func addCoin(address: String? = nil) {
        guard vault.coins.isEmpty else { return }
        let asset = CoinMeta(
            chain: .solana,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: KaminoVaultRegistry.usdcMint,
            isNativeToken: false
        )
        let coin = Coin(asset: asset, address: address ?? owner, hexPublicKey: "pub")
        coin.rawBalance = "1000000000"
        vault.coins.append(coin)
    }

    private static let systemProgramId = "11111111111111111111111111111111"
    /// Anywhere that is not the user. Deliberately NOT the fee payer, or the
    /// appended instruction would be a self-transfer and the test would be
    /// asserting against a transaction that moves nothing.
    private static let attackerAddress = "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU"

    private static func key(_ address: String) throws -> [UInt8] {
        let decoded = try XCTUnwrap(Base58.decodeNoCheck(string: address))
        return [UInt8](decoded)
    }

    /// `SystemProgram::transfer`: a `u32` instruction index of 2, then the
    /// lamports as a little-endian `u64`.
    private static func systemTransfer(lamports: UInt64) -> [UInt8] {
        var data: [UInt8] = [2, 0, 0, 0]
        data += withUnsafeBytes(of: lamports.littleEndian) { [UInt8]($0) }
        return data
    }
}

// MARK: - Test doubles

// Protocol conformances keep their declared signatures.
// swiftlint:disable async_without_await unused_parameter

/// Hydrates the vault honestly and answers every build with whatever the test
/// wants served. That split is the point: the app is allowed to trust the
/// registry-checked vault metadata, and is not allowed to trust the transaction.
private final class HostileKaminoService: KaminoServiceProtocol, @unchecked Sendable {
    enum StubError: Error { case unavailable }

    private let lock = NSLock()
    private var _served = KaminoTransactionFixtures.usdcDeposit.source
    private var _positions: [KaminoUserPositionResponse] = []
    private var _lookupTable = KaminoTransactionFixtures.usdcDeposit.lookupTable

    var served: String {
        get { lock.withLock { _served } }
        set { lock.withLock { _served = newValue } }
    }

    var positions: [KaminoUserPositionResponse] {
        get { lock.withLock { _positions } }
        set { lock.withLock { _positions = newValue } }
    }

    /// The table the served vector references. The validator pins it, so a
    /// vector from a different capture needs its own.
    var lookupTable: String {
        get { lock.withLock { _lookupTable } }
        set { lock.withLock { _lookupTable = newValue } }
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        await Task.yield()
        return KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: descriptor.tokenDecimals),
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: descriptor.sharesDecimals),
            lookupTable: lookupTable,
            apy30d: 0,
            // swiftlint:disable:next force_unwrapping
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")!,
            tokenPriceUsd: 1
        )
    }

    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] {
        await Task.yield()
        return positions
    }

    func buildDepositTransaction(owner: String, vault: KaminoVaultDescriptor, amount: KaminoTokenAmount) async throws -> String {
        await Task.yield()
        return served
    }

    func buildWithdrawTransaction(owner: String, vault: KaminoVaultDescriptor, shares: KaminoShareAmount) async throws -> String {
        await Task.yield()
        return served
    }

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse { throw StubError.unavailable }
    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse { throw StubError.unavailable }
    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse { throw StubError.unavailable }
}

/// A network that agrees with everything, so nothing here is refused by
/// simulation — a refusal has to come from the app's own checks or the test
/// proves nothing about them.
private struct PermissiveSolana: KaminoSolanaMeasuring {

    func simulateTransaction(
        base64Transaction: String,
        replaceRecentBlockhash: Bool,
        accountAddresses: [String]
    ) async throws -> SolanaSimulationResult {
        await Task.yield()
        return SolanaSimulationResult(failure: nil, unitsConsumed: 250_000, logs: [])
    }

    func fetchPrioritizationFeeSample() async throws -> UInt64? {
        await Task.yield()
        return nil
    }

    func fetchRentExemptMinimum(size: Int) async throws -> UInt64 {
        await Task.yield()
        return 890_880
    }
}

private struct FixtureLookupTables: SolanaAddressLookupTableFetching {
    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]] {
        await Task.yield()
        return KaminoTransactionFixtures.lookupTables
    }
}

private struct HostileBalanceService: BalanceServiceProtocol {
    func updateBalance(for coin: Coin) async {}
    func refreshSpendableBalanceOrThrow(for coin: Coin) async throws {}
}

// swiftlint:enable async_without_await unused_parameter
