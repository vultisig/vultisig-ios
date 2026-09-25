//
//  SwapDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Covers the three display-layer quote UX behaviours and the signing guardrail:
//   1. The indicative "to" amount is display-only and can never satisfy
//      validation — `validateForm()` still requires a firm `quote`.
//   2. Stale-while-revalidate skeleton gating (`showsQuoteSkeleton`): skeleton
//      only on the first quote of a pair, not on refreshes that have a prior
//      quote, and never across a pair change.
//   3. The immediate fetch path (percentage / paste) skips the keystroke
//      debounce while free typing stays debounced.
//   4. The `~` estimate follows the payout fit of the pair's last firm quote
//      (fee-aware), falls back to spot for a pair without one, and still never
//      satisfies validation.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapDetailsViewModelTests: XCTestCase {

    private var storeToken: TestContextToken?

    override func setUp() async throws {
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
    }

    func testFailedRefreshKeepsDisplayButBlocksTransactionUntilRecovery() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.quoteError = URLError(.timedOut)
        vm.refreshData(vault: vault)
        await vm.waitForQuoteTask()

        XCTAssertNotNil(vm.quote, "A transient outage can retain the displayed estimate")
        XCTAssertFalse(vm.validateForm(), "A failed refresh must disable Continue")
        XCTAssertNil(vm.makeTransaction(), "The retained quote must not reach Verify")
        vm.error = nil
        XCTAssertFalse(vm.validateForm(), "Dismissing an error must not revalidate the quote")
        XCTAssertNil(vm.makeTransaction())

        interactor.quoteError = nil
        vm.refreshData(vault: vault)
        await vm.waitForQuoteTask()
        XCTAssertTrue(vm.validateForm())
        XCTAssertNotNil(vm.makeTransaction())
    }

    func testStructuralRefreshFailureClearsQuoteAndCandidates() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.quoteError = SwapError.tradingHalted
        vm.refreshData(vault: vault)
        await vm.waitForQuoteTask()

        XCTAssertNil(vm.quote)
        XCTAssertTrue(vm.allQuotes.isEmpty)
        XCTAssertNil(vm.makeTransaction())
        XCTAssertTrue(vm.showRefreshCounter, "A lifted halt must recover without editing the form")
        vm.error = nil
        interactor.quoteError = nil
        vm.timer = 1
        vm.updateTimer(vault: vault)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.makeTransaction())
    }

    func testEmptyRefreshResultClearsQuoteAndBlocksTransaction() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.stubbedQuote = nil
        vm.refreshData(vault: vault)
        await vm.waitForQuoteTask()

        XCTAssertNil(vm.quote)
        XCTAssertNil(vm.makeTransaction())
    }

    func testSettingsChangeCannotHandOffPreviousQuote() async {
        let (vm, interactor, vault) = await makeReadyForm()
        vm.snapshotAdvancedSettings()
        vm.advancedSettings.slippage = .custom(bps: 300)
        XCTAssertNil(vm.makeTransaction(), "Settings must match the validated request even before dismissal")
        interactor.quoteError = URLError(.timedOut)
        vm.advancedSettingsSheetDidClose(vault: vault)
        XCTAssertNil(vm.quote, "A changed request cannot retain the old payload")
        await vm.waitForQuoteTask()
        XCTAssertNil(vm.makeTransaction())
    }

    func testInFlightRefreshBlocksTransaction() async {
        let (vm, _, vault) = await makeReadyForm()
        vm.refreshData(vault: vault)
        XCTAssertNotNil(vm.quote)
        XCTAssertFalse(vm.validateForm())
        XCTAssertNil(vm.makeTransaction())
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.makeTransaction())
    }

    func testFeeRefreshFailureRemainsBlockedAfterErrorDismissal() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.computeFeeError = URLError(.timedOut)
        vm.refreshData(vault: vault)
        await vm.waitForQuoteTask()
        vm.error = nil
        XCTAssertNotNil(vm.quote)
        XCTAssertNil(vm.makeTransaction())
    }

    func testSupersededFailureCannotInvalidateNewQuote() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.suspendNextQuote = true
        vm.updateFromAmount(vault: vault, immediate: true)
        for _ in 0..<200 where interactor.suspendedQuote == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard let pending = interactor.suspendedQuote else {
            return XCTFail("The old refresh must be suspended before it is superseded")
        }
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: vault, immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.makeTransaction())

        pending.resume(throwing: SwapError.tradingHalted)
        interactor.suspendedQuote = nil
        for _ in 0..<200 where !interactor.resumedSuspendedQuote {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(interactor.resumedSuspendedQuote)
        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.quote)
        XCTAssertEqual(vm.makeTransaction()?.fromAmount, 2)
    }

    func testSettingsEditDuringRefreshDiscardsResponseAndRevalidatesOnClose() async {
        let (vm, interactor, vault) = await makeReadyForm()
        let originalQuote = vm.quote
        vm.snapshotAdvancedSettings()
        interactor.suspendNextQuote = true
        vm.updateFromAmount(vault: vault, immediate: true)
        for _ in 0..<200 where interactor.suspendedQuote == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard let pending = interactor.suspendedQuote else {
            return XCTFail("The quote must be suspended before editing settings")
        }
        vm.advancedSettings.slippage = .custom(bps: 300)
        let changedQuote = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "200000000"))
        pending.resume(returning: SwapQuoteResult(quote: changedQuote, vultDiscountBps: 0, referralDiscountBps: 0))
        interactor.suspendedQuote = nil
        await vm.waitForQuoteTask()
        XCTAssertEqual(vm.quote, originalQuote, "A mismatched request must not publish its result")
        XCTAssertNil(vm.makeTransaction())

        vm.advancedSettings = .default
        vm.advancedSettingsSheetDidClose(vault: vault)
        await vm.waitForQuoteTask()
        XCTAssertEqual(interactor.fetchQuoteCallCount, 3, "Reverting settings still needs the discarded refresh retried")
        XCTAssertNotNil(vm.makeTransaction())
    }

    func testRevertingSettingsWhileRefreshPendingStartsCurrentRequest() async {
        let (vm, interactor, vault) = await makeReadyForm()
        vm.snapshotAdvancedSettings()
        vm.advancedSettings.slippage = .custom(bps: 300)
        interactor.suspendNextQuote = true
        vm.updateFromAmount(vault: vault, immediate: true)
        for _ in 0..<200 where interactor.suspendedQuote == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard let pending = interactor.suspendedQuote else {
            return XCTFail("The changed-settings request must be in flight")
        }
        XCTAssertNil(vm.quote)
        vm.advancedSettings = .default
        vm.advancedSettingsSheetDidClose(vault: vault)
        await vm.waitForQuoteTask()
        XCTAssertEqual(interactor.fetchQuoteCallCount, 3)
        XCTAssertNotNil(vm.makeTransaction())
        pending.resume(throwing: SwapError.tradingHalted)
        interactor.suspendedQuote = nil
        for _ in 0..<200 where !interactor.resumedSuspendedQuote {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.makeTransaction())
    }

    private func makeReadyForm() async -> (SwapDetailsViewModel, MockSwapInteractor, Vault) {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        interactor.fee = 1
        let vm = makeVM(interactor: interactor)
        let vault = makeVault()
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: vault, immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertTrue(vm.validateForm(), "Precondition: a successful quote and fee refresh enables Continue")
        XCTAssertNotNil(vm.makeTransaction())
        return (vm, interactor, vault)
    }

    // MARK: - Hand-off into Verify reads the approval once

    func testContinueCarriesTheApprovalReadAtTheHandOff() async throws {
        let (vm, interactor, vault) = await makeReadyForm()
        let query = ERC20ApprovalQuery(chain: .ethereum, token: "0xtoken", owner: "0xowner", spender: "0xrouter", amount: 1)
        interactor.approvalDecision = ERC20ApprovalDecision(query: query, requirement: .resetThenApprove)

        let prepared = await vm.prepareTransaction(vault: vault)
        let transaction = try XCTUnwrap(prepared)

        XCTAssertEqual(interactor.resolveApprovalCallCount, 1)
        XCTAssertEqual(transaction.approvalDecision, interactor.approvalDecision)
        XCTAssertFalse(vm.isLoadingTransaction)
    }

    /// A failed read stays on the form with the error shown, exactly like a
    /// failed quote or fee read, and Continue stays blocked until it is dismissed.
    func testFailedApprovalReadDoesNotEnterVerify() async {
        let (vm, interactor, vault) = await makeReadyForm()
        interactor.approvalError = RpcServiceError.rpcError(code: -32005, message: "rate limit exceeded")

        let transaction = await vm.prepareTransaction(vault: vault)

        XCTAssertNil(transaction, "Verify must not be entered on a guessed approval")
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.validateForm(), "The error blocks Continue until dismissed")
        XCTAssertFalse(vm.isLoadingTransaction)
    }

    // MARK: - Item 1: indicative value is display-only (signing guardrail)

    func testValidateFormFailsWhenOnlyIndicativeAmountPresentAndQuoteNil() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        // No firm quote — only the display-layer indicative could exist.
        vm.quote = nil

        XCTAssertFalse(
            vm.validateForm(),
            "validateForm must require a firm quote; the indicative value must never satisfy it"
        )
    }

    func testMakeTransactionReturnsNilWhenQuoteNil() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.quote = nil

        XCTAssertNil(vm.makeTransaction(), "makeTransaction must never materialise without a firm quote")
    }

    func testIndicativeReturnsNilForNonPositiveAmount() {
        let from = makeCoin(.ethereum, ticker: "ETH")
        let to = makeCoin(.bitcoin, ticker: "BTC")
        XCTAssertNil(SwapCryptoLogic.toAmountIndicative(fromCoin: from, toCoin: to, fromAmount: ""))
        XCTAssertNil(SwapCryptoLogic.toAmountIndicative(fromCoin: from, toCoin: to, fromAmount: "0"))
    }

    // MARK: - Item 2: stale-while-revalidate skeleton gating

    func testFirstQuoteForPairShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // First fetch: no prior quote → leading-edge skeleton should be on.
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        XCTAssertTrue(vm.showsQuoteSkeleton, "First quote of a pair must show the skeleton")

        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)
        XCTAssertFalse(vm.showsQuoteSkeleton, "Skeleton must clear once the firm quote lands")
    }

    func testRefreshWithPriorQuoteDoesNotShowSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Land a firm quote first.
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Auto-refresh on the same pair: the prior quote stays, so no skeleton.
        vm.refreshData(vault: makeVault())
        XCTAssertTrue(vm.isLoadingQuotes, "A refresh is in flight")
        XCTAssertFalse(
            vm.showsQuoteSkeleton,
            "Stale-while-revalidate: a refresh with a prior quote must not blank to skeleton"
        )
        await vm.waitForQuoteTask()
    }

    func testAmountChangeClearsStaleQuoteAndShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Land a firm quote first.
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Editing the amount (same pair) is NOT a silent refresh: the prior
        // quote belongs to the old amount, so it must clear immediately so the
        // "to" field falls back to the indicative estimate and the summary
        // shows its skeleton — stale-while-revalidate is for auto-refresh only.
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        XCTAssertNil(vm.quote, "Quote must clear on an amount change")
        XCTAssertTrue(vm.showsQuoteSkeleton, "An amount change must show the skeleton, not the stale summary")
        await vm.waitForQuoteTask()
    }

    func testPairChangeClearsStaleQuoteAndShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Change the destination coin: the held quote is now meaningless and must
        // be cleared so a different-pair quote can't show through.
        vm.toCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        XCTAssertNil(vm.quote, "Quote must be cleared on a pair change")
        XCTAssertTrue(vm.showsQuoteSkeleton, "A new pair with no prior quote must show the skeleton")
        await vm.waitForQuoteTask()
    }

    func testEmptyAmountClearsQuoteAndPair() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        vm.fromAmount = ""
        vm.updateFromAmount(vault: makeVault())
        XCTAssertNil(vm.quote, "Emptying the amount must clear the quote")
        XCTAssertFalse(vm.showsQuoteSkeleton)
        XCTAssertFalse(vm.isLoadingQuotes)
    }

    // MARK: - Item 3: immediate vs debounced path

    func testImmediatePathResolvesWithoutDebounce() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        let start = Date()
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(vm.quote)
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1)
        XCTAssertLessThan(elapsed, 0.25, "Immediate path must skip the 300ms debounce")
    }

    func testDebouncedPathWaitsForDebounceBeforeFetching() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Default (typing) path is debounced — the network shouldn't be hit
        // before the debounce window elapses.
        vm.updateFromAmount(vault: makeVault())
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(interactor.fetchQuoteCallCount, 0, "Debounced path must not fetch before the debounce")

        await vm.waitForQuoteTask()
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "Debounced path eventually fetches")
    }

    func testLeadingEdgeCancellationSupersedesPendingFetch() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Start a debounced (typing) fetch, then supersede it immediately with a
        // percentage tap — the pending one must be cancelled, only one fetch runs.
        vm.updateFromAmount(vault: makeVault())
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "The superseded debounced fetch must be cancelled")
        XCTAssertNotNil(vm.quote)
    }

    // MARK: - Vault-owned referral code

    func testDetailsQuoteUsesReferralCodeFromVault() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        let vault = makeVault(referredCode: "FRIEND")
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        vm.updateFromAmount(vault: vault, immediate: true)
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.lastReferredCode, "FRIEND")
    }

    func testVerifyRefreshUsesReferralCodeFromVault() async {
        let quote = makeThorQuote(expectedAmountOut: "100000000")
        let interactor = MockSwapInteractor(quote: .thorchain(quote))
        let vault = makeVault(referredCode: "FRIEND")
        let rune = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let transaction = SwapTransaction(
            fromCoin: rune,
            toCoin: btc,
            fromAmount: 1,
            kind: .market(.thorchain(quote)),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune,
            advancedSettings: .default
        )
        let vm = SwapVerifyViewModel(transaction: transaction, interactor: interactor)

        await vm.refreshData(vault: vault)

        XCTAssertEqual(interactor.lastReferredCode, "FRIEND")
    }

    // MARK: - Advanced-settings reset is TOKEN-driven, not chain-driven (leak prevention)
    //
    // A custom slippage / gas-limit / external recipient must never carry into
    // the next swap. The reset fires on the TOKEN-level changes — a from/to coin
    // pick and a flip. A chain switch does NOT reset on its own: it only resets
    // via the resulting token change (the screen's fromCoin/toCoin `onChange` →
    // updateFromCoin/updateToCoin). This avoids wiping a still-valid recipient
    // when only the chain context changes without changing the selected token.

    func testSwitchCoinsResetsAdvancedSettings() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromCoins = [vm.fromCoin]
        vm.advancedSettings.slippage = .custom(bps: 300)
        vm.advancedSettings.externalRecipient = "0xExternalRecipient"
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        // Empty amount keeps `fetchQuotes` from touching the network.
        vm.switchCoins(vault: makeVault())

        XCTAssertEqual(vm.advancedSettings, .default, "Flipping the pair must reset advanced settings")
    }

    func testUpdateFromCoinResetsAdvancedSettings() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromCoins = [vm.fromCoin]
        vm.advancedSettings.gasLimit = 300_000
        vm.advancedSettings.externalRecipient = "0xExternalRecipient"
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        // Picking a new source token resets — empty amount keeps it off-network.
        vm.updateFromCoin(coin: makeCoin(.thorChain, ticker: "RUNE"), vault: makeVault())

        XCTAssertEqual(vm.advancedSettings, .default, "Picking a new source token must reset advanced settings")
    }

    func testUpdateToCoinResetsAdvancedSettings() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.advancedSettings.slippage = .preset(bps: 100)
        vm.advancedSettings.externalRecipient = "bc1qExternalRecipient"
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        // Picking a new destination token resets.
        vm.updateToCoin(coin: makeCoin(.thorChain, ticker: "RUNE"), vault: makeVault())

        XCTAssertEqual(vm.advancedSettings, .default, "Picking a new destination token must reset advanced settings")
    }

    func testHandleFromChainUpdateDoesNotResetAdvancedSettingsOnItsOwn() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromCoins = [vm.fromCoin]
        var settings = SwapAdvancedSettings.default
        settings.gasLimit = 300_000
        settings.externalRecipient = "0xExternalRecipient"
        vm.advancedSettings = settings
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        // Drive a real source-chain switch: target THORChain, with a matching
        // native coin in the vault so `getDefaultCoin` resolves and the guard passes.
        let vault = makeVault()
        vault.coins.append(makeCoin(.thorChain, ticker: "RUNE"))
        vm.fromChain = .thorChain

        vm.handleFromChainUpdate(vault: vault)

        XCTAssertEqual(vm.fromCoin.chain, .thorChain, "Precondition: the source chain actually changed")
        // The handler must NOT reset on its own — the reset is token-driven and in
        // the app fires via the resulting fromCoin `onChange` → updateFromCoin.
        XCTAssertEqual(vm.advancedSettings, settings, "A chain switch alone must not reset advanced settings")
    }

    func testHandleToChainUpdateDoesNotResetAdvancedSettingsOnItsOwn() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        var settings = SwapAdvancedSettings.default
        settings.slippage = .preset(bps: 100)
        settings.externalRecipient = "bc1qExternalRecipient"
        vm.advancedSettings = settings
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        let vault = makeVault()
        vault.coins.append(makeCoin(.thorChain, ticker: "RUNE"))
        vm.toChain = .thorChain

        vm.handleToChainUpdate(vault: vault)

        XCTAssertEqual(vm.toCoin.chain, .thorChain, "Precondition: the destination chain actually changed")
        XCTAssertEqual(vm.advancedSettings, settings, "A chain switch alone must not reset advanced settings")
    }

    func testLoadResetsAdvancedSettingsAtSessionStart() {
        let vm = makeVM()
        var settings = SwapAdvancedSettings.default
        settings.slippage = .custom(bps: 275)
        settings.externalRecipient = "0xLeftoverRecipient"
        vm.advancedSettings = settings
        XCTAssertNotEqual(vm.advancedSettings, .default, "Precondition: settings are non-default")

        let vault = makeVault()
        vault.coins.append(makeCoin(.ethereum, ticker: "ETH", balance: "1"))

        vm.load(initialFromCoin: nil, initialToCoin: nil, vault: vault)

        XCTAssertEqual(vm.advancedSettings, .default, "A new swap session (load) must start at default advanced settings")
    }

    // MARK: - Fee-error surfacing (real error, not a money verdict)

    func testUpdateFeesSurfacesRealErrorInsteadOfInsufficientGas() async {
        // A non-UTXO fee failure (timeout / decode / TLS) must surface as itself.
        // It was previously relabeled by the `default:` branch as
        // `insufficientGas` — a confident money verdict the app can't justify.
        // Driven through the public quote→fee pipeline: the quote resolves, then
        // the fee computation throws, exercising `updateFees`' catch.
        struct ProbeFeeError: Error {}
        let interactor = MockSwapInteractor(
            quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")),
            computeFeeError: ProbeFeeError()
        )
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()

        XCTAssertNotNil(vm.quote, "Precondition: the quote must resolve so updateFees runs")
        XCTAssertTrue(vm.error is ProbeFeeError, "The real fee error must surface, got \(String(describing: vm.error))")
        XCTAssertFalse(vm.error is SwapCryptoLogic.Errors, "A generic fee failure must not be relabeled as a money error")
    }

    // MARK: - Item 4: the `~` estimate follows the pair's last firm quote

    /// 1 RUNE → 0.98 BTC after 0.02 BTC of fees, 0.01 of it the flat outbound
    /// fee: rate 1, proportional 1%, flat 0.01.
    private var feeBearingQuote: SwapQuote {
        .thorchain(makeThorQuote(expectedAmountOut: "98000000", feesTotal: "2000000", feesOutbound: "1000000"))
    }

    func testIndicativeFollowsTheFittedPayoutAfterAnAmountEdit() async {
        let vm = await makeQuotedVM(quote: feeBearingQuote)
        XCTAssertEqual(vm.toAmountDecimal, Decimal(string: "0.98"), "Precondition: the firm quote landed")

        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault())

        XCTAssertNil(vm.quote, "Precondition: an amount edit blanks the firm quote")
        XCTAssertEqual(vm.toAmountIndicative, Decimal(string: "1.97"), "2 × 1 × (1 − 0.01) − 0.01, not a spot ratio")
        XCTAssertTrue(vm.isShowingIndicativeAmount)
        XCTAssertTrue(vm.toAmountDisplayString.hasPrefix("~"))
    }

    func testIndicativeFitIsScopedToThePairItWasFittedOn() async {
        let vm = await makeQuotedVM(quote: feeBearingQuote)
        let btc = vm.toCoin

        vm.updateToCoin(coin: makeCoin(.ethereum, ticker: "ETH"), vault: makeVault())
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault())
        XCTAssertEqual(vm.toAmountIndicative, spotIndicative(vm), "RUNE→ETH has no fit of its own, so it falls back to spot")

        vm.updateToCoin(coin: btc, vault: makeVault())
        XCTAssertEqual(vm.toAmountIndicative, Decimal(string: "1.97"), "Flipping back to the fitted pair restores its fit")
    }

    func testAFirmQuoteOnAnotherPairKeepsTheFirstPairsFit() async {
        let vm = await makeQuotedVM(quote: feeBearingQuote)
        let btc = vm.toCoin

        // RUNE→ETH lands its own firm quote, so it gets its own fit.
        vm.updateToCoin(coin: makeCoin(.ethereum, ticker: "ETH"), vault: makeVault())
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertEqual(vm.payoutFits.count, 2, "Precondition: both pairs have been fitted")

        vm.updateToCoin(coin: btc, vault: makeVault())
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault())

        XCTAssertNil(vm.quote, "Precondition: the amount edit blanks the firm quote")
        XCTAssertEqual(vm.toAmountIndicative, Decimal(string: "1.97"), "RUNE→BTC keeps its fit after RUNE→ETH was quoted")
    }

    func testIndicativeFollowsThePickedRoute() async {
        let vm = await makeQuotedVM(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        vm.selectProvider(.thorchain(makeThorQuote(expectedAmountOut: "50000000")), vault: makeVault())

        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault())

        XCTAssertEqual(vm.toAmountIndicative, 1, "The picked route paid 0.5 per unit, so 2 units estimate to 1")
    }

    func testQuoteLandingAfterAPairChangeIsFittedToThePairItWasFetchedFor() async {
        let interactor = MockSwapInteractor(quote: feeBearingQuote)
        interactor.holdFetch = true
        let vm = makeVM(interactor: interactor)
        let rune = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromCoin = rune
        vm.toCoin = btc
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        for _ in 0..<200 where interactor.fetchQuoteCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "Precondition: the RUNE→BTC fetch is in flight")

        // A chain-picker change assigns the coin directly; the screen's onChange
        // that cancels the fetch has not run yet when the old quote lands.
        vm.toCoin = makeCoin(.ethereum, ticker: "ETH")
        interactor.holdFetch = false
        await vm.waitForQuoteTask()

        XCTAssertEqual(Array(vm.payoutFits.keys), [SwapPairIdentity(fromCoin: rune, toCoin: btc)], "The fit belongs to the pair the quote was fetched for")
        XCTAssertEqual(vm.toAmountIndicative, spotIndicative(vm), "RUNE→ETH must not be priced off a RUNE→BTC quote")
        vm.toCoin = btc
        XCTAssertEqual(vm.toAmountIndicative, Decimal(string: "0.98"), "Fitted with BTC's units, so it prices RUNE→BTC exactly")
    }

    func testQuoteLandingAfterAPairChangeIsNeverPublishedAsTheNewPairsQuote() async {
        let interactor = MockSwapInteractor(quote: feeBearingQuote)
        interactor.holdFetch = true
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        for _ in 0..<200 where interactor.fetchQuoteCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "Precondition: the RUNE→BTC fetch is in flight")

        let eth = makeCoin(.ethereum, ticker: "ETH")
        vm.toCoin = eth
        interactor.holdFetch = false
        await vm.waitForQuoteTask()

        XCTAssertNil(vm.quote, "A RUNE→BTC quote must not be published while the form shows RUNE→ETH")
        XCTAssertEqual(vm.toAmountDecimal, 0)
        XCTAssertFalse(vm.validateForm())
        XCTAssertNil(vm.makeTransaction())

        // The screen's onChange runs next: it must start a fresh RUNE→ETH fetch,
        // not treat the discarded quote as a silent refresh of the new pair.
        vm.updateToCoin(coin: eth, vault: makeVault())
        XCTAssertNil(vm.quote)
        XCTAssertTrue(vm.isLoadingQuotes)
        await vm.waitForQuoteTask()
        XCTAssertEqual(interactor.fetchQuoteCallCount, 2)
        XCTAssertNotNil(vm.quote, "The RUNE→ETH fetch publishes normally")
    }

    func testFittedIndicativeNeverSatisfiesValidationOrSigning() async {
        let vm = await makeQuotedVM(quote: feeBearingQuote)
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault())

        XCTAssertNotNil(vm.toAmountIndicative, "Precondition: a fitted estimate is on screen")
        XCTAssertNil(vm.quote)
        XCTAssertFalse(vm.validateForm())
        XCTAssertEqual(vm.toAmountDecimal, 0)
        XCTAssertNil(vm.makeTransaction())
    }

    // MARK: - Fixtures

    /// The spot-only estimate for the view model's current input. Other suites
    /// seed `RateProvider.shared` in-process, so whether spot is nil or a number
    /// depends on test order; comparing against it keeps the assertion exact.
    private func spotIndicative(_ vm: SwapDetailsViewModel) -> Decimal? {
        SwapCryptoLogic.toAmountIndicative(fromCoin: vm.fromCoin, toCoin: vm.toCoin, fromAmount: vm.fromAmountDecimal)
    }

    /// RUNE → BTC with `quote` landed for 1 RUNE.
    private func makeQuotedVM(quote: SwapQuote) async -> SwapDetailsViewModel {
        let vm = makeVM(interactor: MockSwapInteractor(quote: quote))
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        return vm
    }

    private func makeVM(interactor: SwapInteractor? = nil) -> SwapDetailsViewModel {
        SwapDetailsViewModel(interactor: interactor ?? MockSwapInteractor(quote: nil))
    }

    private func makeVault(referredCode: String? = nil) -> Vault {
        let vault = Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "iPhone-12345",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        if let referredCode {
            vault.referredCode = ReferredCode(code: referredCode, vault: vault)
        }
        return vault
    }

    private func makeCoin(_ chain: Chain, ticker: String, balance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = balance
        return coin
    }

    private func makeThorQuote(
        expectedAmountOut: String = "0",
        feesTotal: String = "0",
        feesOutbound: String = "0"
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "RUNE",
                outbound: feesOutbound,
                total: feesTotal,
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }
}

// MARK: - Test helpers

private extension SwapDetailsViewModel {
    /// Awaits the in-flight quote task so assertions run after it settles.
    /// Polls a short, bounded number of times to avoid coupling to internal task
    /// handles while keeping the test deterministic.
    func waitForQuoteTask() async {
        for _ in 0..<200 where isLoadingQuotes || isLoadingFees {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// swiftlint:disable async_without_await unused_parameter

/// Minimal `SwapInteractor` mock: returns a fixed quote (or none) and records
/// how many times the quote fetch ran so the debounce/immediate paths can be
/// asserted. Fees resolve to zero so the happy path keeps the quote set.
@MainActor
private final class MockSwapInteractor: SwapInteractor {
    var stubbedQuote: SwapQuote?
    var computeFeeError: Error?
    var quoteError: Error?
    var fee: BigInt = .zero
    var suspendNextQuote = false
    var suspendedQuote: CheckedContinuation<SwapQuoteResult?, Error>?
    var resumedSuspendedQuote = false
    private(set) var fetchQuoteCallCount = 0
    private(set) var lastReferredCode: String?
    /// While set, `fetchQuote` parks after being counted, so a test can act
    /// mid-flight and then release it.
    var holdFetch = false
    var approvalDecision: ERC20ApprovalDecision?
    var approvalError: Error?
    private(set) var resolveApprovalCallCount = 0

    init(quote: SwapQuote?, computeFeeError: Error? = nil) {
        self.stubbedQuote = quote
        self.computeFeeError = computeFeeError
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        fetchQuoteCallCount += 1
        lastReferredCode = referredCode
        if suspendNextQuote {
            suspendNextQuote = false
            defer { resumedSuspendedQuote = true }
            return try await withCheckedThrowingContinuation { suspendedQuote = $0 }
        }
        if let quoteError { throw quoteError }
        while holdFetch {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard let stubbedQuote else { return nil }
        return SwapQuoteResult(quote: stubbedQuote, vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        if let computeFeeError {
            throw computeFeeError
        }
        return fee
    }

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func resolveApproval(for transaction: SwapTransaction, vault: Vault) async throws -> ERC20ApprovalDecision? {
        resolveApprovalCallCount += 1
        if let approvalError { throw approvalError }
        return approvalDecision
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}

// swiftlint:enable async_without_await unused_parameter
