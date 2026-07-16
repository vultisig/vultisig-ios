//
//  BalanceServiceMulticallPartitionTests.swift
//  VultisigAppTests
//
//  Covers the write-side of the Multicall3 batch: which coins get a balance
//  written and which are held back for a per-coin retry.
//
//  The bug this pins: a PARTIAL batch failure doesn't throw. `aggregate3` reports
//  success at the top level while an individual sub-call reports success = false,
//  so the batch-level "fall back to per-coin" path never fires. Mapping that
//  sub-call to `0` therefore persisted an empty balance over a funded coin with no
//  throw, no fallback and no log. A failed read and an empty wallet must stay
//  distinguishable all the way to the write.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class BalanceServiceMulticallPartitionTests: XCTestCase {

    private func identifier(ticker: String, isNativeToken: Bool) -> BalanceService.CoinIdentifier {
        let coin = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: ticker, decimals: 18, isNativeToken: isNativeToken),
            address: "0xwallet",
            hexPublicKey: ""
        )
        return BalanceService.CoinIdentifier(from: coin)
    }

    /// `CoinMeta.make` derives the contract address from the ticker.
    private func contract(_ ticker: String) -> String { "\(ticker)-contract" }

    // MARK: - A failed sub-call must never be written as a balance

    func testFailedTokenSubCallProducesNoUpdateSoBalanceIsPreserved() {
        // USDC is absent from `balances` (its sub-call failed). It must yield NO
        // update — `applyBalanceUpdates` only writes coins that carry one, so no
        // update is what preserves the funded coin's last known balance.
        let usdc = identifier(ticker: "USDC", isNativeToken: false)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: nil,
            balances: [:],
            nativeCoins: [],
            tokenCoins: [usdc]
        )

        XCTAssertTrue(updates.isEmpty, "a failed sub-call must not produce a balance write")
        XCTAssertEqual(failed.map { $0.ticker }, ["USDC"], "it must be handed to the per-coin retry")
    }

    func testFailedSubCallDoesNotZeroFundedCoinWhileSiblingsStillUpdate() {
        // The core regression: one reverting token in a multi-token batch must not
        // zero itself, and must not hold its siblings back either.
        let dai = identifier(ticker: "DAI", isNativeToken: false)
        let usdc = identifier(ticker: "USDC", isNativeToken: false)
        let wbtc = identifier(ticker: "WBTC", isNativeToken: false)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: nil,
            balances: [contract("DAI"): BigInt(500), contract("WBTC"): BigInt(200)],
            nativeCoins: [],
            tokenCoins: [dai, usdc, wbtc]
        )

        XCTAssertEqual(failed.map { $0.ticker }, ["USDC"])

        let byId = Dictionary(uniqueKeysWithValues: updates.map { ($0.coinId, $0) })
        XCTAssertNil(byId[usdc.coinId], "the failed coin must have no update to write")
        XCTAssertEqual(byId[dai.coinId]?.rawBalance, "500", "siblings still update")
        XCTAssertEqual(byId[wbtc.coinId]?.rawBalance, "200", "siblings still update")
    }

    func testFailedNativeSubCallProducesNoUpdateWhileTokensUpdate() {
        let eth = identifier(ticker: "ETH", isNativeToken: true)
        let dai = identifier(ticker: "DAI", isNativeToken: false)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: nil,
            balances: [contract("DAI"): BigInt(7)],
            nativeCoins: [eth],
            tokenCoins: [dai]
        )

        XCTAssertEqual(failed.map { $0.ticker }, ["ETH"])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.coinId, dai.coinId)
    }

    // MARK: - A genuine zero is still a real balance

    func testGenuineZeroBalanceStillWritesZero() {
        // An empty wallet must render as empty. "Preserve on failure" must not turn
        // into "never write zero" — that would strand a coin the user just drained.
        let dai = identifier(ticker: "DAI", isNativeToken: false)
        let eth = identifier(ticker: "ETH", isNativeToken: true)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: BigInt(0),
            balances: [contract("DAI"): BigInt(0)],
            nativeCoins: [eth],
            tokenCoins: [dai]
        )

        XCTAssertTrue(failed.isEmpty, "a genuine zero is a successful read, not a failure")
        XCTAssertEqual(updates.count, 2)
        for update in updates {
            XCTAssertEqual(update.rawBalance, "0")
            XCTAssertTrue(update.hasUpdates, "a zero balance must still reach the write")
        }
    }

    func testZeroAndFailureAreDistinguishableInTheSameBatch() {
        // The whole point of the fix, in one assertion pair: same batch, one token
        // genuinely at zero, one token failed — they must not come out the same.
        let empty = identifier(ticker: "EMPTY", isNativeToken: false)
        let broken = identifier(ticker: "BROKEN", isNativeToken: false)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: nil,
            balances: [contract("EMPTY"): BigInt(0)],
            nativeCoins: [],
            tokenCoins: [empty, broken]
        )

        XCTAssertEqual(updates.map { $0.coinId }, [empty.coinId])
        XCTAssertEqual(updates.first?.rawBalance, "0", "genuine zero → written as 0")
        XCTAssertEqual(failed.map { $0.coinId }, [broken.coinId], "failed → retried, not written")
    }

    // MARK: - The preservation mechanism itself

    func testUpdateWithoutRawBalanceReportsNothingToWrite() {
        // `hasUpdates` is the predicate `applyBalanceUpdates` filters on
        // (`for update in updates where update.hasUpdates`), so a nil rawBalance
        // reporting `false` here is what makes "no update" mean "keep the last
        // known balance". This asserts the predicate only — the end-to-end
        // fetchEvmBatchBalances -> fallbackPerCoin -> applyBalanceUpdates
        // integration is not unit-testable (EvmService is a non-injectable enum
        // factory) and was verified at runtime instead, against a live batch with
        // a deliberately reverting sub-call.
        let update = BalanceService.CoinBalanceUpdate(
            coinId: "eth-coin",
            rawBalance: nil,
            stakedBalance: nil,
            bondedNodes: nil,
            error: nil
        )

        XCTAssertFalse(update.hasUpdates, "a nil rawBalance must not reach the coin")
    }

    func testFullySuccessfulBatchNeedsNoPerCoinRetry() {
        let eth = identifier(ticker: "ETH", isNativeToken: true)
        let dai = identifier(ticker: "DAI", isNativeToken: false)

        let (updates, failed) = BalanceService.partitionBatchResult(
            native: BigInt(11),
            balances: [contract("DAI"): BigInt(22)],
            nativeCoins: [eth],
            tokenCoins: [dai]
        )

        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates.first(where: { $0.coinId == eth.coinId })?.rawBalance, "11")
        XCTAssertEqual(updates.first(where: { $0.coinId == dai.coinId })?.rawBalance, "22")
    }
}
