//
//  UnmergeTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate and balance-fetch ordering for the THORChain RUJI UNMERGE
//  form. `transactionBuilder` returning nil is the enforcement — `FormScreen`
//  does not disable Continue on `validForm` — so every rejection is asserted
//  through the builder, not through a flag.
//
//  The two tests that pay for this file are the ones the legacy sub-model got
//  wrong: a share count that only survives as an integer, and a second token
//  selected while the first token's balance is still in flight.
//

import BigInt
@testable import VultisigApp
import XCTest

@MainActor
final class UnmergeTransactionViewModelTests: XCTestCase {

    private static let kujiDenom = "thor.kuji"
    private static let rkujiDenom = "thor.rkuji"
    private static let kujiContract = "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"
    private static let rkujiContract = "thor1yyca08xqdgvjz0psg56z67ejh9xms6l436u8y58m82npdqqhmmtqrsjrgh"

    // MARK: - Fixtures

    private static func makeThorchainToken(_ ticker: String) -> Coin {
        FunctionActionFixture.makeCoin(
            .thorChain,
            ticker: ticker,
            decimals: 8,
            isNative: false,
            address: FunctionActionFixture.thorAddress
        )
    }

    /// Amount strings in this file are written dot-decimal, so the view-model is
    /// pinned to `en_US` rather than inheriting the runner's locale — the parser
    /// deliberately refuses an amount written in another locale's convention, so
    /// a comma-decimal machine would otherwise fail these for environmental
    /// reasons. `testTheMaxPathIsExact` opts back out, because the string it
    /// feeds is produced by the app's own locale-aware formatter.
    private func makeViewModel(
        shares: [String: String] = [:],
        vaultCoins: [Coin]? = nil,
        initialDenom: String? = nil,
        stub: StubMergeBalanceSource? = nil,
        locale: Locale = Locale(identifier: "en_US")
    ) -> (UnmergeTransactionViewModel, StubMergeBalanceSource) {
        let source = stub ?? StubMergeBalanceSource()
        source.sharesByDenom.merge(shares) { _, new in new }
        let rune = FunctionActionFixture.makeRUNE()
        let vault = FunctionActionFixture.makeVault(coins: vaultCoins ?? [rune])
        let viewModel = UnmergeTransactionViewModel(
            coin: rune,
            vault: vault,
            initialDenom: initialDenom,
            balanceSource: source,
            locale: locale
        )
        return (viewModel, source)
    }

    private func token(_ denom: String) -> THORChainAsset {
        MergeTokenCatalog.tokens.first { $0.thorchainAsset == denom }!
    }

    /// Polls a condition on the main actor. The form's balance read lands from a
    /// detached `Task`, so there is nothing to `await` on directly.
    private func waitFor(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline {
                return XCTFail("Timed out waiting for \(description)", file: file, line: line)
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// One main-actor turn, so a write-back scheduled by a just-completed
    /// request has run before the assertion reads the state it would have
    /// touched.
    private func settleMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    // MARK: - Pre-selection

    func testOpensOnTheFirstOfferedTokenWhenTheCallerKnowsNone() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()

        XCTAssertEqual(viewModel.selectedToken?.thorchainAsset, Self.kujiDenom)
        await waitFor("the balance to land") { viewModel.availableShares == BigInt(500_000_000) }
    }

    func testOpensOnTheDenomTheCallerNamed() async {
        let (viewModel, _) = makeViewModel(
            shares: [Self.rkujiDenom: "700000000"],
            initialDenom: Self.rkujiDenom
        )
        viewModel.onLoad()

        XCTAssertEqual(viewModel.selectedToken?.thorchainAsset, Self.rkujiDenom)
        await waitFor("the balance to land") { viewModel.availableShares == BigInt(700_000_000) }
    }

    func testAnUnknownDenomFallsBackToTheFirstOfferedToken() {
        let (viewModel, _) = makeViewModel(initialDenom: "thor.notatoken")
        viewModel.onLoad()

        XCTAssertEqual(viewModel.selectedToken?.thorchainAsset, Self.kujiDenom)
    }

    // MARK: - Validity gate

    func testPristineFormDoesNotBuild() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        XCTAssertEqual(viewModel.amountField.value, "")
        XCTAssertNil(viewModel.transactionBuilder, "An empty share amount must not produce an unmerge memo")
        XCTAssertEqual(viewModel.amountField.error, "enterValidAmount".localized)
    }

    func testZeroAndJunkAmountsDoNotBuild() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        for input in ["0", "0.000000004", "abc", "-1"] {
            viewModel.amountField.value = input
            XCTAssertNil(viewModel.transactionBuilder, "\(input) must not build")
        }
    }

    /// The ceiling is the raw share count, compared as an integer — not the
    /// displayed decimal.
    func testAnAmountAboveTheAvailableSharesDoesNotBuild() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = "5.00000001"
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.amountField.error, "insufficientBalanceForFunctions".localized)

        viewModel.amountField.value = "5"
        XCTAssertNotNil(viewModel.transactionBuilder, "Exactly the available shares is allowed")
    }

    /// A balance that never arrives leaves the ceiling at zero, so nothing
    /// builds — the legacy form validated against a stale `availableBalance`
    /// instead.
    func testNothingBuildsWhileTheBalanceIsUnknown() async {
        let (viewModel, source) = makeViewModel()
        source.errorByDenom[Self.kujiDenom] = HelperError.runtimeError("boom")
        viewModel.onLoad()
        await waitFor("the failure to land") { viewModel.sharesLabel == "errorLoadingBalance".localized }

        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.availableShares, .zero)
    }

    // MARK: - The memo, end to end

    /// The migration's point, exercised through the form rather than the
    /// builder: a share count past what a `Double` holds is typed, validated
    /// and encoded without losing a digit.
    func testAShareCountThatWouldRoundThroughDoubleReachesTheMemoIntact() async {
        let (viewModel, _) = makeViewModel(
            shares: [Self.kujiDenom: "99999999999999999999"],
            vaultCoins: [FunctionActionFixture.makeRUNE(), Self.makeThorchainToken("KUJI")]
        )
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = "123456789.12345679"

        let builder = viewModel.transactionBuilder as? UnmergeTransactionBuilder
        XCTAssertEqual(builder?.shares, BigInt("12345678912345679"))
        XCTAssertEqual(builder?.memo, "unmerge:thor.kuji:12345678912345679")
        XCTAssertEqual(builder?.amount, "0", "Shares ride the memo, never the transaction")
    }

    func testTheBuilderCarriesTheSelectedTokensMergeContract() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = "1"
        let builder = viewModel.transactionBuilder as? UnmergeTransactionBuilder
        XCTAssertEqual(builder?.contractAddress, Self.kujiContract)
        XCTAssertEqual(builder?.toAddress, Self.kujiContract)
        XCTAssertEqual(builder?.denom, Self.kujiDenom)
    }

    /// The 100% button writes `availableAmount.formatToDecimal(digits:)` into
    /// the field — the app's own locale-aware formatter — and the parser reads it
    /// back. This is the path `AmountTextField.setupAmount()` takes, minus the
    /// view, and it has to land on exactly the shares the account holds or "max"
    /// silently leaves some behind. Runs in the machine's own locale on purpose:
    /// the formatter and the parser have to agree about the same one.
    func testTheMaxPathRoundTripsToTheExactShareCount() async {
        let (viewModel, _) = makeViewModel(
            shares: [Self.kujiDenom: "123456789123456"],
            locale: .current
        )
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = viewModel.availableAmount.formatToDecimal(digits: UnmergeShares.decimals)

        let builder = viewModel.transactionBuilder as? UnmergeTransactionBuilder
        XCTAssertEqual(builder?.shares, viewModel.availableShares)
        XCTAssertEqual(builder?.memo, "unmerge:thor.kuji:123456789123456")
    }

    // MARK: - Which coin signs

    /// The legacy screen pointed the transaction at the merged token whenever
    /// the vault held it. Preserved, so the verify screen and history still name
    /// the token being withdrawn.
    func testTheBuilderSignsOnTheVaultsMergedTokenWhenItIsHeld() async {
        let (viewModel, _) = makeViewModel(
            shares: [Self.kujiDenom: "500000000"],
            vaultCoins: [FunctionActionFixture.makeRUNE(), Self.makeThorchainToken("KUJI")]
        )
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = "1"
        XCTAssertEqual(viewModel.transactionBuilder?.coin.ticker, "KUJI")
    }

    /// And falls back to the chain's native asset when it is not — the same
    /// no-op the legacy coin binding left in place. Nothing signed depends on
    /// it: the wasm execute names the contract, and every THORChain coin shares
    /// one address.
    func testTheBuilderFallsBackToRuneWhenTheMergedTokenIsNotHeld() async {
        let (viewModel, _) = makeViewModel(shares: [Self.kujiDenom: "500000000"])
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }

        viewModel.amountField.value = "1"
        XCTAssertEqual(viewModel.transactionBuilder?.coin.ticker, "RUNE")
    }

    // MARK: - Latest-wins (the named defect)

    /// Select A, then B before A answers. The legacy form dropped B's request
    /// outright (`if isLoading { return }`) and kept A's shares under B's name.
    func testASecondSelectionIsFetchedEvenWhileTheFirstIsInFlight() async {
        let (viewModel, source) = makeViewModel(
            shares: [Self.kujiDenom: "100000000", Self.rkujiDenom: "222222222"]
        )
        source.gatedDenoms.insert(Self.kujiDenom)
        viewModel.onLoad()
        await waitFor("the first request to park") { source.isParked(Self.kujiDenom) }

        viewModel.select(token(Self.rkujiDenom))
        await waitFor("the second balance to land") { viewModel.availableShares == BigInt(222_222_222) }

        XCTAssertEqual(source.requestedDenoms, [Self.kujiDenom, Self.rkujiDenom])
    }

    /// And when the first request finally answers, it must not land on top of
    /// the second. This is the write the generation stamp refuses — cancellation
    /// alone cannot, because the response had already resolved.
    func testAStaleBalanceNeverOverwritesTheCurrentSelection() async {
        let (viewModel, source) = makeViewModel(
            shares: [Self.kujiDenom: "100000000", Self.rkujiDenom: "222222222"]
        )
        source.gatedDenoms.insert(Self.kujiDenom)
        viewModel.onLoad()
        await waitFor("the first request to park") { source.isParked(Self.kujiDenom) }

        viewModel.select(token(Self.rkujiDenom))
        await waitFor("the second balance to land") { viewModel.availableShares == BigInt(222_222_222) }

        source.release(Self.kujiDenom)
        // Causal, not timed: assert only once the released response has actually
        // finished producing, so a reverted generation guard cannot pass by
        // simply being slower than the wait.
        await waitFor("the stale response to finish") { source.completedDenoms.contains(Self.kujiDenom) }
        await settleMainActor()

        XCTAssertEqual(viewModel.selectedToken?.thorchainAsset, Self.rkujiDenom)
        XCTAssertEqual(viewModel.availableShares, BigInt(222_222_222))
        XCTAssertFalse(viewModel.isLoading)

        viewModel.amountField.value = "2.22222222"
        let builder = viewModel.transactionBuilder as? UnmergeTransactionBuilder
        XCTAssertEqual(builder?.memo, "unmerge:thor.rkuji:222222222")
        XCTAssertEqual(builder?.contractAddress, Self.rkujiContract)
    }

    /// The stale response must not resurrect the previous token's ceiling
    /// either — the amount typed against B's balance stays judged against B's.
    func testAStaleFailureDoesNotClearTheCurrentBalance() async {
        let (viewModel, source) = makeViewModel(shares: [Self.rkujiDenom: "222222222"])
        source.gatedDenoms.insert(Self.kujiDenom)
        source.errorByDenom[Self.kujiDenom] = HelperError.runtimeError("boom")
        viewModel.onLoad()
        await waitFor("the first request to park") { source.isParked(Self.kujiDenom) }

        viewModel.select(token(Self.rkujiDenom))
        await waitFor("the second balance to land") { viewModel.availableShares == BigInt(222_222_222) }

        source.release(Self.kujiDenom)
        await waitFor("the stale failure to finish") { source.completedDenoms.contains(Self.kujiDenom) }
        await settleMainActor()

        XCTAssertEqual(viewModel.availableShares, BigInt(222_222_222))
        XCTAssertEqual(viewModel.sharesLabel, "sharesLabel".localized)
    }

    /// Switching tokens clears the amount: an amount typed against one token's
    /// share balance means nothing under another's.
    func testSwitchingTokensClearsTheTypedAmount() async {
        let (viewModel, _) = makeViewModel(
            shares: [Self.kujiDenom: "500000000", Self.rkujiDenom: "222222222"]
        )
        viewModel.onLoad()
        await waitFor("the balance to land") { viewModel.availableShares > 0 }
        viewModel.amountField.value = "1"

        viewModel.select(token(Self.rkujiDenom))
        XCTAssertEqual(viewModel.amountField.value, "")
        XCTAssertNil(viewModel.transactionBuilder)
    }
}

/// Merge-account source whose responses can be parked per denom, so a test can
/// make the *first* selection answer after the second.
private final class StubMergeBalanceSource: RujiMergeBalanceSource, @unchecked Sendable {
    var sharesByDenom: [String: String] = [:]
    var errorByDenom: [String: Error] = [:]
    var gatedDenoms: Set<String> = []

    private var parked: [String: CheckedContinuation<Void, Never>] = [:]
    private var requested: [String] = []
    private var completed: [String] = []
    private let lock = NSLock()

    var requestedDenoms: [String] {
        lock.withLock { requested }
    }

    /// Denoms whose response has finished producing — the causal signal the
    /// stale-response tests wait on instead of a timer.
    var completedDenoms: [String] {
        lock.withLock { completed }
    }

    func isParked(_ denom: String) -> Bool {
        lock.withLock { parked[denom.lowercased()] != nil }
    }

    func release(_ denom: String) {
        let key = denom.lowercased()
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            gatedDenoms.remove(key)
            return parked.removeValue(forKey: key)
        }
        continuation?.resume()
    }

    func fetchRujiMergeBalance(thorAddr _: String, tokenSymbol: String) async throws -> ThorchainService.RujiBalance {
        let key = tokenSymbol.lowercased()
        let isGated: Bool = lock.withLock {
            requested.append(key)
            return gatedDenoms.contains(key)
        }

        if isGated {
            await withCheckedContinuation { continuation in
                lock.withLock { parked[key] = continuation }
            }
        }

        if let error = lock.withLock({ errorByDenom[key] }) {
            lock.withLock { completed.append(key) }
            throw error
        }

        let shares = lock.withLock { sharesByDenom[key] } ?? "0"
        lock.withLock { completed.append(key) }
        return ThorchainService.RujiBalance(ruji: 0, shares: shares, price: 0)
    }
}
