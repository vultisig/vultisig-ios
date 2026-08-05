//
//  KaminoTransactionPreparerTests.swift
//  VultisigAppTests
//
//  This is the first Kamino code that can move a user's money, so the tests are
//  about the pipeline's *order* and its *refusals*, not about happy-path plumbing.
//
//  Three properties carry the fund-safety argument, and each has its own case:
//
//  1. The transaction is validated TWICE, against opposite contracts — before
//     injection any ComputeBudget instruction is a refusal, after injection both
//     are required and pinned. Collapsing them would make an injected fee
//     indistinguishable from one the API supplied.
//  2. Nothing is returned that has not simulated cleanly, at the exact bytes that
//     will be signed.
//  3. The SOL reserve is measured from the transaction, not assumed.
//

import BigInt
@testable import VultisigApp
import XCTest

final class KaminoTransactionPreparerTests: XCTestCase {

    private let owner = KaminoTransactionFixtures.usdcDeposit.feePayer
    private let solOwner = KaminoTransactionFixtures.solDeposit.feePayer
    private let withdrawOwner = KaminoTransactionFixtures.usdcWithdraw.feePayer

    // MARK: - The pipeline reproduces the mainnet-proven bytes

    /// The strongest assertion available: the preparer's output for the sampled
    /// USDC deposit is byte-identical to the vector that was injected by the
    /// reference implementation and simulated on mainnet with `err: null`.
    func testUsdcDepositProducesTheMainnetSimulatedBytes() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)

        let prepared = try await harness.preparer.prepareDeposit(
            vault: Self.steakhouseVault,
            owner: owner,
            amount: Self.usdcAmount,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(prepared.base64, KaminoTransactionFixtures.usdcDeposit.injected)
        XCTAssertEqual(prepared.priorityFee.limit, KaminoComputeBudget.tokenDepositUnitLimit)
        XCTAssertEqual(prepared.priorityFee.price, KaminoTransactionFixtures.unitPriceMicroLamports)
    }

    /// The SOL vault deposit does strictly more work — it creates the wrapped-SOL
    /// account, transfers into it and syncs it — so it gets the higher limit. A
    /// shared limit would be a silent under-budget on the more expensive one.
    func testSolDepositUsesTheHigherComputeLimit() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.solDeposit)

        let prepared = try await harness.preparer.prepareDeposit(
            vault: Self.allezVault,
            owner: solOwner,
            amount: Self.solAmount,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(prepared.base64, KaminoTransactionFixtures.solDeposit.injected)
        XCTAssertEqual(prepared.priorityFee.limit, KaminoComputeBudget.nativeDepositUnitLimit)
        XCTAssertGreaterThan(
            KaminoComputeBudget.nativeDepositUnitLimit,
            KaminoComputeBudget.tokenDepositUnitLimit
        )
    }

    /// `SolanaHelper.priorityFeeLimit` is 100,000 CU and every Kamino transaction
    /// consumes more than that, so reusing it would abort each of them on compute
    /// exhaustion. Pinned here as well as in the step-2 tests because this is the
    /// first code that actually chooses a limit.
    func testEveryDepositLimitClearsTheGenericSolanaLimit() {
        let generic = SolanaHelper.priorityFeeLimit
        XCTAssertGreaterThan(BigInt(KaminoComputeBudget.tokenDepositUnitLimit), generic)
        XCTAssertGreaterThan(BigInt(KaminoComputeBudget.nativeDepositUnitLimit), generic)
    }

    // MARK: - Withdraw

    /// The same assertion the deposits get: the preparer's output for the
    /// sampled withdraw is byte-identical to the vector that was injected by the
    /// reference implementation and simulated on mainnet with `err: null`.
    func testUsdcWithdrawProducesTheMainnetSimulatedBytes() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcWithdraw)

        let prepared = try await harness.preparer.prepareWithdraw(
            vault: Self.steakhouseWithdrawVault,
            owner: withdrawOwner,
            request: Self.usdcRequest,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(prepared.base64, KaminoTransactionFixtures.usdcWithdraw.injected)
        XCTAssertEqual(prepared.priorityFee.limit, KaminoComputeBudget.withdrawUnitLimit)
        XCTAssertEqual(prepared.priorityFee.price, KaminoTransactionFixtures.unitPriceMicroLamports)
    }

    /// The request is sized in SHARES. The API takes the same `amount` field for
    /// both actions with inverted units, so this is the assertion that the
    /// withdraw path never hands it a token figure.
    func testTheWithdrawRequestIsDenominatedInShares() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcWithdraw)

        _ = try await harness.preparer.prepareWithdraw(
            vault: Self.steakhouseWithdrawVault,
            owner: withdrawOwner,
            request: Self.usdcRequest,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(harness.service.withdrawRequests.first?.shares, Self.usdcShares)
        XCTAssertEqual(harness.service.withdrawRequests.first?.vault, KaminoVaultRegistry.steakhouseUSDC)
        XCTAssertTrue(harness.service.depositRequests.isEmpty)
    }

    /// The withdraw limit has to clear the generic Solana constant AND the most
    /// expensive withdraw shape, which is the farm-staked one on the wrapped-SOL
    /// vault at 309,310 units — not the 173,385 an unstaked withdraw costs.
    func testTheWithdrawLimitClearsTheGenericSolanaLimit() {
        XCTAssertGreaterThan(BigInt(KaminoComputeBudget.withdrawUnitLimit), SolanaHelper.priorityFeeLimit)
        XCTAssertGreaterThan(KaminoComputeBudget.withdrawUnitLimit, 309_310)
    }

    /// Phase one's contract on the withdraw path too: a response that already
    /// carries a ComputeBudget instruction is a fee the app did not choose.
    func testAWithdrawResponseThatAlreadyCarriesAComputeBudgetIsRefused() async {
        let harness = Harness(
            vector: KaminoTransactionFixtures.usdcWithdraw,
            served: KaminoTransactionFixtures.usdcWithdraw.injected
        )

        do {
            _ = try await harness.preparer.prepareWithdraw(
                vault: Self.steakhouseWithdrawVault,
                owner: withdrawOwner,
                request: Self.usdcRequest,
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected the pre-injection validation to refuse a supplied compute budget")
        } catch let error as KaminoValidationError {
            XCTAssertEqual(error, .unexpectedPriorityFee(index: 0))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertTrue(harness.solana.simulatedTransactions.isEmpty)
    }

    /// The backstop that makes the `u64::MAX` sentinel unreachable. The
    /// validator pins the withdraw instruction's argument to exactly the shares
    /// that were requested, so a response carrying "withdraw everything" is
    /// refused before simulation and before any signature.
    func testAResponseThatRewroteTheAmountToTheSentinelIsRefused() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcWithdraw)
        // The sampled transaction burns 5,500,000 shares. Asking for one fewer
        // makes the response's amount the larger of the two — the shape a
        // silently widened withdraw has.
        let requested = KaminoShareAmount(baseUnits: BigInt(5_499_999), decimals: 6)

        do {
            _ = try await harness.preparer.prepareWithdraw(
                vault: Self.steakhouseWithdrawVault,
                owner: withdrawOwner,
                request: KaminoWithdrawRequest(shares: requested, unstakedShares: requested),
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected an amount mismatch")
        } catch let error as KaminoValidationError {
            XCTAssertEqual(
                error,
                .amountMismatch(role: "withdraw share amount", expected: "5499999", actual: "5500000")
            )
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertTrue(harness.solana.simulatedTransactions.isEmpty)
    }

    /// A withdraw that would not execute never reaches a signer, whatever the
    /// reason — including the one this feature cannot yet name, a vault without
    /// the liquid balance to settle it.
    func testAWithdrawThatWouldFailIsRefused() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcWithdraw)
        harness.solana.results = [.failed("{InstructionError: [1, {Custom: 6003}]}"), .ok(payer: nil)]

        do {
            _ = try await harness.preparer.prepareWithdraw(
                vault: Self.steakhouseWithdrawVault,
                owner: withdrawOwner,
                request: Self.usdcRequest,
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected a refusal")
        } catch let error as KaminoPreparationError {
            guard case .simulationFailed(let stage, _) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(stage, .asBuilt)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Two-phase validation

    /// The order the whole contract rests on: build, validate with no fee,
    /// simulate, inject, validate with the fee, simulate again.
    func testValidationRunsOnceBeforeInjectionAndOnceAfter() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)

        _ = try await harness.preparer.prepareDeposit(
            vault: Self.steakhouseVault,
            owner: owner,
            amount: Self.usdcAmount,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(harness.solana.simulatedTransactions.count, 2)
        XCTAssertEqual(harness.solana.simulatedTransactions[0], KaminoTransactionFixtures.usdcDeposit.source)
        XCTAssertEqual(harness.solana.simulatedTransactions[1], KaminoTransactionFixtures.usdcDeposit.injected)
    }

    /// Phase one's contract, exercised end to end: a response that already
    /// carries a ComputeBudget instruction is a fee the app did not choose, and
    /// the preparer must refuse it rather than inject on top or accept it.
    func testAResponseThatAlreadyCarriesAComputeBudgetIsRefused() async {
        // The injected vector IS a Kamino transaction with ComputeBudget
        // instructions, which is exactly the shape a compromised response would
        // have — so serving it as the API's answer is the real attack.
        let harness = Harness(
            vector: KaminoTransactionFixtures.usdcDeposit,
            served: KaminoTransactionFixtures.usdcDeposit.injected
        )

        do {
            _ = try await harness.preparer.prepareDeposit(
                vault: Self.steakhouseVault,
                owner: owner,
                amount: Self.usdcAmount,
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected the pre-injection validation to refuse a supplied compute budget")
        } catch let error as KaminoValidationError {
            XCTAssertEqual(error, .unexpectedPriorityFee(index: 0))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        // Nothing may be simulated after a refusal either — the refusal is the
        // end of the pipeline, not a warning it walks past.
        XCTAssertTrue(harness.solana.simulatedTransactions.isEmpty)
    }

    /// Phase two's contract: the injected instructions are pinned to the values
    /// the app chose. Driven here by making the amount disagree, which is the
    /// same second pass catching a different substitution.
    func testTheSecondPassStillChecksTheAmount() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)
        let wrongAmount = KaminoTokenAmount(baseUnits: BigInt(9_999_999), decimals: 6)

        do {
            _ = try await harness.preparer.prepareDeposit(
                vault: Self.steakhouseVault,
                owner: owner,
                amount: wrongAmount,
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected an amount mismatch")
        } catch let error as KaminoValidationError {
            guard case .amountMismatch(let role, _, _) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(role, "deposit amount")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Simulation is a gate, not a report

    func testATransactionThatWouldFailAsBuiltIsRefused() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)
        harness.solana.results = [
            .failed("{InstructionError: [1, {Custom: 6003}]}"),
            .ok(payer: nil)
        ]

        await assertPreparationFails(harness, stage: .asBuilt)
    }

    /// The bytes that get signed are the injected ones, so the run that matters
    /// most is the one after injection — a limit that turned out too low would
    /// only show up here.
    func testATransactionThatWouldFailAfterInjectionIsRefused() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)
        harness.solana.results = [
            .ok(payer: nil),
            .failed("ProgramFailedToComplete")
        ]

        await assertPreparationFails(harness, stage: .budgeted)
    }

    // MARK: - Priority price

    func testTheSampledPriceIsClampedIntoABoundedRange() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)

        harness.solana.prioritizationFee = .success(UInt64.max)
        var price = await harness.preparer.resolveUnitPrice()
        XCTAssertEqual(price, KaminoComputeBudget.maxUnitPriceMicroLamports)

        harness.solana.prioritizationFee = .success(1)
        price = await harness.preparer.resolveUnitPrice()
        XCTAssertEqual(price, KaminoComputeBudget.fallbackUnitPriceMicroLamports)

        harness.solana.prioritizationFee = .success(120_000)
        price = await harness.preparer.resolveUnitPrice()
        XCTAssertEqual(price, 120_000)
    }

    /// A sample the app could not read is not a reason to refuse a deposit — the
    /// fallback is a usable price, and the transaction is proven by simulation
    /// either way.
    func testAFailedPriceSampleFallsBackRatherThanThrowing() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)
        harness.solana.prioritizationFee = .failure

        let price = await harness.preparer.resolveUnitPrice()

        XCTAssertEqual(price, KaminoComputeBudget.fallbackUnitPriceMicroLamports)
    }

    /// A quiet network — nobody paying a priority fee at all — must land on this
    /// feature's own floor, not on the generic Solana default. That default is
    /// 1,000,000 µlamports, which is also this clamp's ceiling, so inheriting it
    /// would silently tip fifty times over on exactly the network conditions
    /// where no tip is needed.
    func testAnEmptyFeeSampleUsesTheKaminoFloorNotTheGenericDefault() async {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)
        harness.solana.prioritizationFee = .noSample

        let price = await harness.preparer.resolveUnitPrice()

        XCTAssertEqual(price, KaminoComputeBudget.fallbackUnitPriceMicroLamports)
        XCTAssertNotEqual(price, SolanaHelper.defaultPriorityFeePrice)
    }

    /// The ceiling has to actually bound the fee in lamports, which is the number
    /// the user pays. `limit × price / 1_000_000` at the largest limit.
    func testThePriceCeilingBoundsTheFeeInLamports() {
        let worstCase = UInt64(KaminoComputeBudget.nativeDepositUnitLimit)
            * KaminoComputeBudget.maxUnitPriceMicroLamports / 1_000_000
        XCTAssertEqual(worstCase, 350_000)
    }

    // MARK: - SOL reserve

    /// The reserve is the payer's measured lamport delta, so the maximum is what
    /// the payer would be left holding plus what the probe deposited, less the
    /// floor a wallet account has to stay above.
    ///
    /// A wallet account left with a non-zero balance below its rent-exempt
    /// minimum is rejected on chain (`InsufficientFundsForRent`), so a maximum
    /// that spent into that band would build a transaction that cannot execute.
    func testTheMaximumIsDerivedFromTheMeasuredPayerBalance() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.solDeposit)
        let probe = KaminoTokenAmount(baseUnits: BigInt(500_000_000), decimals: 9)
        harness.solana.results = [.ok(payer: nil), .ok(payer: 1_500_000_000)]
        harness.solana.rentExemptMinimum = 890_880

        let maximum = try await harness.preparer.maxNativeDepositLamports(
            vault: Self.allezVault,
            owner: solOwner,
            probe: probe,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(maximum, BigInt(1_500_000_000) + probe.baseUnits - BigInt(890_880))
        XCTAssertEqual(harness.solana.rentExemptSizes, [0])
    }

    /// The reserve the measurement implies is the transaction's real cost, not a
    /// guess at "fee plus two rents". Reproduced here from the same numbers so a
    /// future change that reintroduces a constant fails.
    func testTheImpliedReserveIsWhateverTheTransactionActuallySpends() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.solDeposit)
        let probe = KaminoTokenAmount(baseUnits: BigInt(500_000_000), decimals: 9)
        // A wallet holding 3 SOL that is left with 2.49 SOL after depositing 0.5
        // spent 0.01 SOL on the transaction itself.
        let balance = BigInt(3_000_000_000)
        harness.solana.results = [.ok(payer: nil), .ok(payer: 2_490_000_000)]
        harness.solana.rentExemptMinimum = 890_880

        let maximum = try await harness.preparer.maxNativeDepositLamports(
            vault: Self.allezVault,
            owner: solOwner,
            probe: probe,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        let impliedReserve = balance - maximum
        XCTAssertEqual(impliedReserve, BigInt(10_000_000) + BigInt(890_880))
    }

    /// A node that ran the transaction but did not report the payer leaves the
    /// cost unknown. Guessing one would be the failure this whole approach exists
    /// to avoid, so it refuses.
    func testAnUnreportedPayerBalanceRefusesRatherThanGuessing() async {
        let harness = Harness(vector: KaminoTransactionFixtures.solDeposit)
        harness.solana.results = [.ok(payer: nil), .ok(payer: nil)]

        do {
            _ = try await harness.preparer.maxNativeDepositLamports(
                vault: Self.allezVault,
                owner: solOwner,
                probe: KaminoTokenAmount(baseUnits: BigInt(500_000_000), decimals: 9),
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected a refusal")
        } catch let error as KaminoPreparationError {
            XCTAssertEqual(error, .payerBalanceUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The clamp. Defensive rather than routine — reaching it needs the payer to
    /// end at zero AND the rent floor to exceed the probe, which a real wallet
    /// that could afford the probe at all never does. It exists because a
    /// negative maximum would render as a nonsense balance and, worse, would
    /// underflow every comparison built on it.
    func testAWalletBelowTheReserveHasNothingAvailable() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.solDeposit)
        harness.solana.results = [.ok(payer: nil), .ok(payer: 0)]
        harness.solana.rentExemptMinimum = 600_000_000

        let maximum = try await harness.preparer.maxNativeDepositLamports(
            vault: Self.allezVault,
            owner: solOwner,
            probe: Self.solAmount,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(maximum, 0)
    }

    /// The payer's balance is only meaningful for the bytes that will be signed,
    /// so the accounts request rides the *second* simulation.
    func testThePayerIsOnlyAskedForOnTheFinalSimulation() async throws {
        let harness = Harness(vector: KaminoTransactionFixtures.usdcDeposit)

        _ = try await harness.preparer.prepareDeposit(
            vault: Self.steakhouseVault,
            owner: owner,
            amount: Self.usdcAmount,
            unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
        )

        XCTAssertEqual(harness.solana.requestedAccounts, [[], [owner]])
    }

    // MARK: - Helpers

    private func assertPreparationFails(
        _ harness: Harness,
        stage: KaminoPreparationError.Stage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await harness.preparer.prepareDeposit(
                vault: Self.steakhouseVault,
                owner: owner,
                amount: Self.usdcAmount,
                unitPrice: KaminoTransactionFixtures.unitPriceMicroLamports
            )
            XCTFail("expected a refusal", file: file, line: line)
        } catch let error as KaminoPreparationError {
            guard case .simulationFailed(let failedStage, _) = error else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(failedStage, stage, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

// MARK: - Fixtures

private extension KaminoTransactionPreparerTests {

    static let usdcAmount = KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
    static let solAmount = KaminoTokenAmount(baseUnits: BigInt(500_000_000), decimals: 9)
    /// The share count the sampled withdraw vector burns.
    static let usdcShares = KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)
    /// The sampled wallet held these shares unstaked, so the request needs no
    /// farm release and the transaction carries no farms instruction.
    static let usdcRequest = KaminoWithdrawRequest(shares: usdcShares, unstakedShares: usdcShares)

    static var steakhouseVault: KaminoVaultInfo {
        vaultInfo(
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            lookupTable: KaminoTransactionFixtures.usdcDeposit.lookupTable,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: 6)
        )
    }

    /// Same vault, and the same lookup table — the withdraw vector references it
    /// too — named separately so the withdraw cases read as their own.
    static var steakhouseWithdrawVault: KaminoVaultInfo {
        vaultInfo(
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            lookupTable: KaminoTransactionFixtures.usdcWithdraw.lookupTable,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: 6)
        )
    }

    static var allezVault: KaminoVaultInfo {
        vaultInfo(
            descriptor: KaminoVaultRegistry.allezSOL,
            lookupTable: KaminoTransactionFixtures.solDeposit.lookupTable,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 9)
        )
    }

    static func vaultInfo(
        descriptor: KaminoVaultDescriptor,
        lookupTable: String,
        minDeposit: KaminoTokenAmount
    ) -> KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: minDeposit,
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: descriptor.sharesDecimals),
            lookupTable: lookupTable,
            apy30d: 0,
            // swiftlint:disable:next force_unwrapping
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")!,
            tokenPriceUsd: 1
        )
    }

    /// One preparer wired to fakes, plus the fakes themselves.
    final class Harness {
        let service: StubKaminoService
        let solana: StubSolanaMeasuring
        let preparer: KaminoTransactionPreparer

        init(vector: KaminoTransactionFixtures.Vector, served: String? = nil) {
            service = StubKaminoService(transaction: served ?? vector.source)
            solana = StubSolanaMeasuring()
            preparer = KaminoTransactionPreparer(
                service: service,
                solana: solana,
                validator: KaminoTransactionValidator(
                    lookupTableSource: StubLookupTables(tables: KaminoTransactionFixtures.lookupTables)
                )
            )
        }
    }
}

// MARK: - Test doubles

// Protocol conformances keep their declared signatures, so unused parameters and
// `async` without `await` are unavoidable here.
// swiftlint:disable async_without_await unused_parameter

private struct StubLookupTables: SolanaAddressLookupTableFetching {
    let tables: [String: [String]]

    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]] {
        await Task.yield()
        return tables
    }
}

/// Serves one pre-captured transaction. The REST layer is covered by
/// `KaminoServiceTests`; what matters here is what the preparer does with a
/// response, including a hostile one.
private final class StubKaminoService: KaminoServiceProtocol, @unchecked Sendable {
    enum StubError: Error { case notUsedHere }

    let transaction: String
    private let lock = NSLock()
    private var _depositRequests: [(owner: String, vault: KaminoVaultDescriptor, amount: KaminoTokenAmount)] = []
    private var _withdrawRequests: [(owner: String, vault: KaminoVaultDescriptor, shares: KaminoShareAmount)] = []

    var depositRequests: [(owner: String, vault: KaminoVaultDescriptor, amount: KaminoTokenAmount)] {
        lock.withLock { _depositRequests }
    }

    var withdrawRequests: [(owner: String, vault: KaminoVaultDescriptor, shares: KaminoShareAmount)] {
        lock.withLock { _withdrawRequests }
    }

    init(transaction: String) {
        self.transaction = transaction
    }

    func buildDepositTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        amount: KaminoTokenAmount
    ) async throws -> String {
        lock.withLock { _depositRequests.append((owner, vault, amount)) }
        return transaction
    }

    func buildWithdrawTransaction(owner: String, vault: KaminoVaultDescriptor, shares: KaminoShareAmount) async throws -> String {
        lock.withLock { _withdrawRequests.append((owner, vault, shares)) }
        return transaction
    }

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse { throw StubError.notUsedHere }
    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse { throw StubError.notUsedHere }
    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo { throw StubError.notUsedHere }
    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] { throw StubError.notUsedHere }
    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse { throw StubError.notUsedHere }
}

/// Scripted simulation outcomes, in the order the preparer asks for them.
private final class StubSolanaMeasuring: KaminoSolanaMeasuring, @unchecked Sendable {

    enum Outcome {
        case ok(payer: UInt64?)
        case failed(String)
    }

    enum Sample {
        case success(UInt64)
        /// The network reported no non-zero prioritization fee.
        case noSample
        case failure
    }

    enum StubError: Error { case sampleUnavailable }

    private let lock = NSLock()
    private var _simulated: [String] = []
    private var _requestedAccounts: [[String]] = []
    private var _rentExemptSizes: [Int] = []
    private var _results: [Outcome] = [.ok(payer: nil), .ok(payer: nil)]
    private var _prioritizationFee: Sample = .success(KaminoComputeBudget.fallbackUnitPriceMicroLamports)
    private var _rentExemptMinimum: UInt64 = 890_880
    private var _cursor = 0

    var simulatedTransactions: [String] { lock.withLock { _simulated } }
    var requestedAccounts: [[String]] { lock.withLock { _requestedAccounts } }
    var rentExemptSizes: [Int] { lock.withLock { _rentExemptSizes } }

    var results: [Outcome] {
        get { lock.withLock { _results } }
        set { lock.withLock { _results = newValue; _cursor = 0 } }
    }

    var prioritizationFee: Sample {
        get { lock.withLock { _prioritizationFee } }
        set { lock.withLock { _prioritizationFee = newValue } }
    }

    var rentExemptMinimum: UInt64 {
        get { lock.withLock { _rentExemptMinimum } }
        set { lock.withLock { _rentExemptMinimum = newValue } }
    }

    func simulateTransaction(
        base64Transaction: String,
        replaceRecentBlockhash: Bool,
        accountAddresses: [String]
    ) async throws -> SolanaSimulationResult {
        await Task.yield()
        let outcome: Outcome = lock.withLock {
            _simulated.append(base64Transaction)
            _requestedAccounts.append(accountAddresses)
            let index = min(_cursor, _results.count - 1)
            _cursor += 1
            return _results[index]
        }

        switch outcome {
        case .failed(let reason):
            return SolanaSimulationResult(failure: reason, unitsConsumed: 0, logs: [])
        case .ok(let payer):
            var lamports: [String: UInt64] = [:]
            if let payer, let address = accountAddresses.first {
                lamports[address] = payer
            }
            return SolanaSimulationResult(
                failure: nil,
                unitsConsumed: 252_146,
                logs: [],
                accountLamports: lamports
            )
        }
    }

    func fetchPrioritizationFeeSample() async throws -> UInt64? {
        await Task.yield()
        switch prioritizationFee {
        case .success(let value):
            return value
        case .noSample:
            return nil
        case .failure:
            throw StubError.sampleUnavailable
        }
    }

    func fetchRentExemptMinimum(size: Int) async throws -> UInt64 {
        await Task.yield()
        return lock.withLock {
            _rentExemptSizes.append(size)
            return _rentExemptMinimum
        }
    }
}

// swiftlint:enable async_without_await unused_parameter
