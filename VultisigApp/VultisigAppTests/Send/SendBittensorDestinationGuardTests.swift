//
//  SendBittensorDestinationGuardTests.swift
//  VultisigAppTests
//
//  Covers `SendCryptoVerifyLogic.validateBittensorDestinationIfNeeded`: the
//  pre-ceremony guard that blocks a native TAO send which would leave the
//  DESTINATION below the 500-rao existential deposit, and its FAIL-OPEN
//  posture on a lookup that couldn't complete (matching the XRP guards in
//  SendRippleDestinationGuardTests).
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendBittensorDestinationGuardTests: XCTestCase {

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testNonBittensorSendSkipsBalanceLookup() async throws {
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let tx = makeTransaction(coin: eth, amount: amount("0.1"))

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
        XCTAssertEqual(bittensorService.callCount, 0)
    }

    func testTaoTokenNotNativeSkipsBalanceLookup() async throws {
        // Guards the isNativeToken gate: a non-native Bittensor coin (were one
        // ever added) must not trigger a native-account ED check.
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let taoToken = makeCoin(.bittensor, ticker: "SUBTOKEN", decimals: 9, isNative: false)
        let tx = makeTransaction(coin: taoToken, amount: amount("0.1"))

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
        XCTAssertEqual(bittensorService.callCount, 0)
    }

    func testUnfundedDestinationReceivingAtLeastEDPasses() async throws {
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        // 0.000001 TAO = 1000 rao, above the 500-rao ED.
        let tx = makeTransaction(coin: tao, amount: amount("0.000001"))

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
        XCTAssertEqual(bittensorService.callCount, 1)
    }

    func testUnfundedDestinationReceivingExactlyEDPasses() async throws {
        // The boundary itself: `transfer_keep_alive` permits landing exactly
        // on the ED (only strictly below it is rejected), so this must pass —
        // mirrors the DOT/TAO `canBeReaped` boundary tests in
        // SendValidationTests.
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        let tx = makeTransaction(coin: tao, amount: amount("0.0000005")) // exactly 500 rao

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
    }

    func testDestinationLeftBelowExistentialDepositThrows() async throws {
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        // 0.0000004 TAO = 400 rao — a brand-new destination would land below
        // the 500-rao ED and be reaped by the runtime.
        let tx = makeTransaction(coin: tao, amount: amount("0.0000004"))

        do {
            try await logic.validateBittensorDestinationIfNeeded(tx: tx)
            XCTFail("expected belowExistentialDepositDestinationError")
        } catch {
            XCTAssertEqual(error.localizedDescription, "belowExistentialDepositDestinationError".localized)
        }
    }

    func testDestinationAlreadyFundedAboveEDPasses() async throws {
        // An existing balance plus a small top-up that individually would be
        // sub-ED must still pass: the guard checks the RESULTING balance.
        let bittensorService = StubBittensorBalanceFetching(result: .success("10000000")) // 0.01 TAO
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        let tx = makeTransaction(coin: tao, amount: amount("0.0000001")) // 100 rao

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
    }

    func testUnparseableBalanceResponseFailsOpen() async throws {
        // An unreadable response is not evidence of anything and must not be
        // coerced to "zero balance" — that would fail CLOSED and block a
        // send the guard has no real basis to reject.
        let bittensorService = StubBittensorBalanceFetching(result: .success("not-a-number"))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        let tx = makeTransaction(coin: tao, amount: amount("0.0000004")) // 400 rao — sub-ED if read as 0

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
    }

    func testNodeErrorFailsOpen() async throws {
        struct DummyError: Error {}
        let bittensorService = StubBittensorBalanceFetching(result: .failure(DummyError()))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        // Would be below ED if the lookup answered — but it can't, so the send
        // must proceed rather than block on a failed read.
        let tx = makeTransaction(coin: tao, amount: amount("0.0000004"))

        try await logic.validateBittensorDestinationIfNeeded(tx: tx)
    }

    func testCancellationPropagatesRatherThanBeingReadAsEvidence() async throws {
        let bittensorService = StubBittensorBalanceFetching(result: .failure(CancellationError()))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        let tx = makeTransaction(coin: tao, amount: amount("0.0000004"))

        do {
            try await logic.validateBittensorDestinationIfNeeded(tx: tx)
            XCTFail("expected CancellationError to propagate")
        } catch is CancellationError {
            // expected
        }
    }

    /// The gap the round-1 Codex finding closed: `getBalance` can answer from
    /// a cache with no suspension point that would observe cancellation, so
    /// the guard has to ask the task itself. The stub here SUCCEEDS — this
    /// exercises the post-fetch `try Task.checkCancellation()`, not the
    /// `catch is CancellationError` branch the test above covers. Mirrors
    /// `SendRippleDestinationGuardTests.testDestinationTrustLineGuardPropagatesCancellation`.
    func testCancellationObservedEvenWhenBalanceReadSucceeds() async throws {
        let bittensorService = StubBittensorBalanceFetching(result: .success("0"))
        let logic = makeLogic(bittensorService: bittensorService)
        let tao = makeCoin(.bittensor, ticker: "TAO", decimals: 9)
        // Would throw belowExistentialDepositDestinationError if evaluated —
        // the guard must abort on cancellation before it gets that far.
        let tx = makeTransaction(coin: tao, amount: amount("0.0000004"))

        let task = Task {
            // Suspend first so the cancel below always lands before the guard
            // runs, regardless of scheduling order.
            try? await Task.sleep(for: .seconds(60))
            try await logic.validateBittensorDestinationIfNeeded(tx: tx)
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("a cancelled destination lookup must abort the load pass")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - Helpers

    /// Re-renders a canonical dot-decimal amount string into the current
    /// locale's decimal separator. The send helpers parse with
    /// `Locale.current` first, so a literal like "0.0000004" misparses under
    /// comma-decimal locales (e.g. en_AR on a dev machine, where "." reads as
    /// a grouping separator). Building the amount with the active separator
    /// keeps these unit tests deterministic across locales — same helper as
    /// `SendValidationTests`.
    private func amount(_ canonical: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        return canonical.replacingOccurrences(of: ".", with: separator)
    }

    private func makeLogic(bittensorService: BittensorBalanceFetching) -> SendCryptoVerifyLogic {
        SendCryptoVerifyLogic(
            interactor: MockSendInteractor(),
            bittensorService: bittensorService
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool = true) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: "send-bittensor-guard-\(ticker)",
            contractAddress: isNative ? "" : "sub-token",
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "5Ej64CJQSZFsPK4byPVCZhNWiYeRXnELwYw4KYQBq6yfvaQ3", hexPublicKey: "")
    }

    private func makeTransaction(coin: Coin, amount: String) -> SendTransaction {
        let vault = TestStore.makeVault()
        return SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuXG",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: BigInt(200_000),
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }
}

private final class StubBittensorBalanceFetching: BittensorBalanceFetching, @unchecked Sendable {
    private let result: Result<String, Error>
    private(set) var callCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    // The protocol requirement is async; this stub has no network round-trip
    // to await, and `address` only matters to the real service.
    // swiftlint:disable:next async_without_await unused_parameter
    func getBalance(address: String) async throws -> String {
        callCount += 1
        return try result.get()
    }
}
