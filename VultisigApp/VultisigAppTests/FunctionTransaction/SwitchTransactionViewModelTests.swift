//
//  SwitchTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate and route resolution for the Cosmos Hub → THORChain SWITCH
//  form. `transactionBuilder` returning nil is the enforcement — `FormScreen`
//  does not disable Continue on `validForm` — so every rejection is asserted
//  through the builder, not through a flag.
//
//  The tests that pay for this file are the two the legacy sub-model got wrong:
//  the destination address it resolved once at form load and reused, and the
//  halted route it logged and swallowed.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class SwitchTransactionViewModelTests: XCTestCase {

    // `nonisolated` throughout: these feed default arguments, which are
    // evaluated outside the test case's main-actor isolation.
    private nonisolated static let thorTarget = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"
    private nonisolated static let otherThorTarget = "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z"
    private nonisolated static let mayaNode = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"
    private nonisolated static let inboundA = "cosmos1ghheq4u67c7szhg02whqj4sgg4tlt8mgdhteyk"
    private nonisolated static let inboundB = "cosmos1zg69v7yszg69v7yszg69v7yszg69v7ysd8ep6q"

    // MARK: - Fixtures

    private static func makeRune() -> Coin {
        FunctionCallFixture.makeCoin(
            .thorChain,
            ticker: "RUNE",
            decimals: 8,
            isNative: true,
            rawBalance: "100000000000",
            address: thorTarget
        )
    }

    /// `nonisolated` so it can be used as a default argument, which is
    /// evaluated outside the test case's main-actor isolation.
    private nonisolated static func makeInbound(
        chain: String = "GAIA",
        address: String = inboundA,
        halted: Bool = false,
        globalPaused: Bool? = false,
        chainPaused: Bool? = false,
        lpPaused: Bool? = false
    ) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: address,
            router: nil,
            halted: halted,
            global_trading_paused: globalPaused,
            chain_trading_paused: chainPaused,
            chain_lp_actions_paused: lpPaused,
            gas_rate: "450000",
            gas_rate_units: "uatom",
            dust_threshold: "1",
            outbound_fee: "24512100",
            outbound_tx_size: "1"
        )
    }

    /// ATOM is six-decimal; `10000000` raw is a balance of 10.
    private func makeViewModel(
        inbounds: [InboundAddress] = [SwitchTransactionViewModelTests.makeInbound()],
        holdsRune: Bool = true,
        rawBalance: String = "10000000",
        locale: Locale = Locale(identifier: "en_US")
    ) -> (SwitchTransactionViewModel, StubInboundSource) {
        let atom = FunctionCallFixture.makeATOM(rawBalance: rawBalance)
        let source = StubInboundSource()
        source.inbounds = inbounds
        let coins = holdsRune ? [atom, Self.makeRune()] : [atom]
        let viewModel = SwitchTransactionViewModel(
            coin: atom,
            vault: FunctionCallFixture.makeVault(coins: coins),
            inboundSource: source,
            locale: locale
        )
        return (viewModel, source)
    }

    /// Polls a condition on the main actor. The route read lands from a
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

    private func loadedViewModel(
        inbounds: [InboundAddress] = [SwitchTransactionViewModelTests.makeInbound()],
        holdsRune: Bool = true,
        rawBalance: String = "10000000",
        locale: Locale = Locale(identifier: "en_US")
    ) async -> (SwitchTransactionViewModel, StubInboundSource) {
        let (viewModel, source) = makeViewModel(
            inbounds: inbounds,
            holdsRune: holdsRune,
            rawBalance: rawBalance,
            locale: locale
        )
        viewModel.onLoad()
        await waitFor("the load-time route probe to land") { viewModel.routeState != .resolving }
        return (viewModel, source)
    }

    // MARK: - Prefill

    /// Pin: legacy `init` prefilled the THORChain address from the vault.
    func testPrefillsTheThorchainAddressFromTheVault() async {
        let (viewModel, _) = await loadedViewModel()
        XCTAssertEqual(viewModel.thorAddressViewModel.field.value, Self.thorTarget)
    }

    func testLeavesTheThorchainAddressEmptyWhenTheVaultHasNone() async {
        let (viewModel, _) = await loadedViewModel(holdsRune: false)
        XCTAssertEqual(viewModel.thorAddressViewModel.field.value, "")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// Legacy seeded the amount with the whole balance; SWITCH moves the gas
    /// asset, so a pre-filled 100% could never be signed.
    func testTheAmountStartsEmpty() async {
        let (viewModel, _) = await loadedViewModel()
        XCTAssertEqual(viewModel.amountField.value, "")
        XCTAssertNil(viewModel.transactionBuilder, "A pristine amount must not produce a SWITCH transfer")
    }

    // MARK: - Address validation

    /// Tighter than the legacy sub-model, which accepted a THOR *or* Maya *or*
    /// TON address here. The memo credits a THORChain account, so a maya1…
    /// destination was a silent loss.
    func testAMayaAddressIsRejected() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.thorAddressViewModel.field.value = Self.mayaNode
        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testGarbageAddressIsRejected() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.thorAddressViewModel.field.value = "not-an-address"
        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testAnEmptyAddressIsRejected() async {
        let (viewModel, _) = await loadedViewModel(holdsRune: false)
        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertNotNil(viewModel.thorAddressViewModel.field.error)
    }

    // MARK: - Amount validation

    /// Pin: legacy's submit gate required `amount <= coin.balanceDecimal`.
    func testAnAmountOverTheBalanceIsRejected() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.amountField.value = "10.000001"
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.amountField.error, "amountExceeded".localized)

        viewModel.amountField.value = "10"
        XCTAssertNotNil(viewModel.transactionBuilder, "Exactly the balance is allowed")
    }

    /// Pin: legacy's submit gate required `amount > 0`.
    func testZeroAndJunkAmountsAreRejected() async {
        let (viewModel, _) = await loadedViewModel()
        for input in ["0", "0.0", "abc", "-1", ""] {
            viewModel.amountField.value = input
            XCTAssertNil(viewModel.transactionBuilder, "\(input) must not build")
        }
    }

    /// The locale hazard, through the form: an `en_US` field handed a
    /// comma-decimal amount refuses it rather than reading it as ten times the
    /// intended transfer.
    func testAnAmountInTheOtherLocalesConventionIsRefused() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.amountField.value = "1,5"
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.amountField.error, "invalidAmount".localized)
    }

    /// And the same amount in a comma-decimal locale is one and a half, not
    /// fifteen — which would be over the ten-ATOM balance and rejected anyway,
    /// so the assertion is on the attached value.
    func testACommaDecimalLocaleReadsTheAmountAsWritten() async {
        let (viewModel, _) = await loadedViewModel(locale: Locale(identifier: "de_DE"))
        viewModel.amountField.value = "1,5"

        let builder = viewModel.transactionBuilder as? SwitchTransactionBuilder
        XCTAssertEqual(builder?.switchAmount, Decimal(string: "1.5"))
    }

    // MARK: - The memo and the transfer

    func testTheBuilderCarriesTheMemoAndTheAmount() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.amountField.value = "2.5"

        let builder = viewModel.transactionBuilder as? SwitchTransactionBuilder
        XCTAssertEqual(builder?.memo, "SWITCH:\(Self.thorTarget)")
        XCTAssertEqual(builder?.switchAmount, Decimal(string: "2.5"))
        XCTAssertEqual(builder?.toAddress, Self.inboundA)
        XCTAssertEqual(builder?.coin.ticker, "ATOM")
    }

    /// A hand-typed THORChain address other than the vault's own is honoured —
    /// the field is editable, as it was in the legacy form.
    func testAnEditedThorchainAddressReachesTheMemo() async {
        let (viewModel, _) = await loadedViewModel()
        viewModel.thorAddressViewModel.field.value = Self.otherThorTarget
        viewModel.amountField.value = "1"

        XCTAssertEqual(viewModel.transactionBuilder?.memo, "SWITCH:\(Self.otherThorTarget)")
    }

    // MARK: - The inbound address is resolved on the tap

    /// The named defect. THORChain churns its inbound vaults; the legacy
    /// sub-model resolved one from a five-minute cache when the form opened and
    /// reused it for the life of the screen, which is how a transfer ends up at
    /// a retired vault. The address the transaction carries must be the one
    /// fetched on the tap.
    func testTheBuilderUsesTheAddressFetchedOnTheTapNotTheOneFetchedAtLoad() async {
        let (viewModel, source) = await loadedViewModel()
        XCTAssertEqual(viewModel.routeState, .available(inboundAddress: Self.inboundA))

        viewModel.amountField.value = "1"
        source.inbounds = [Self.makeInbound(address: Self.inboundB)]

        let builder = await viewModel.prepareTransactionBuilder() as? SwitchTransactionBuilder
        XCTAssertEqual(builder?.inboundAddress, Self.inboundB)
        XCTAssertEqual(builder?.toAddress, Self.inboundB)
    }

    /// And that read must not be served from the five-minute cache the load
    /// probe warms.
    func testTheTapReadBypassesTheCache() async {
        let (viewModel, source) = await loadedViewModel()
        XCTAssertEqual(source.bypassCacheCalls, [false], "The load probe may use the cache")

        viewModel.amountField.value = "1"
        _ = await viewModel.prepareTransactionBuilder()

        XCTAssertEqual(source.bypassCacheCalls, [false, true])
    }

    /// An invalid form never reaches the network at all.
    func testAnInvalidFormDoesNotReResolveTheRoute() async {
        let (viewModel, source) = await loadedViewModel()
        viewModel.amountField.value = "0"

        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder)
        XCTAssertEqual(source.bypassCacheCalls, [false])
    }

    // MARK: - Halted routes

    /// The other named defect: legacy logged the halt and returned, leaving an
    /// empty destination in an editable field with nothing on screen to explain
    /// it.
    func testAHaltedRouteIsSurfacedAndCannotBeSignedInto() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [Self.makeInbound(halted: true)])

        XCTAssertEqual(viewModel.routeState, .halted(chain: "GAIA"))
        XCTAssertEqual(viewModel.routeMessage, String(format: "inboundPaused".localized, "GAIA"))

        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder)
        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder, "A halted route must not produce a transaction")
    }

    func testGlobalAndPerChainTradingPausesAlsoBlock() async {
        for inbound in [
            Self.makeInbound(globalPaused: true),
            Self.makeInbound(chainPaused: true)
        ] {
            let (viewModel, _) = await loadedViewModel(inbounds: [inbound])
            viewModel.amountField.value = "1"
            XCTAssertEqual(viewModel.routeState, .halted(chain: "GAIA"))
            let builder = await viewModel.prepareTransactionBuilder()
            XCTAssertNil(builder)
        }
    }

    /// `chain_lp_actions_paused` is the `PauseLP` mimir — it suspends
    /// liquidity-provider actions only, and THORChain leaves it set on healthy
    /// chains for long stretches. A SWITCH is a plain transfer, so it must not
    /// be blocked by it.
    func testAnLPActionsPauseDoesNotBlockASwitch() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [Self.makeInbound(lpPaused: true)])
        viewModel.amountField.value = "1"
        XCTAssertEqual(viewModel.routeState, .available(inboundAddress: Self.inboundA))
        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNotNil(builder)
    }

    /// The whole reason the destination is re-read on the tap rather than
    /// trusted from load: a route that was open when the form opened can be
    /// halted by the time the user is ready to sign.
    func testARouteThatHaltsWhileTheFormIsOpenBlocksTheTap() async {
        let (viewModel, source) = await loadedViewModel()
        viewModel.amountField.value = "1"
        XCTAssertNotNil(viewModel.transactionBuilder)

        source.inbounds = [Self.makeInbound(halted: true)]

        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder)
        XCTAssertEqual(viewModel.routeMessage, String(format: "inboundPaused".localized, "GAIA"))
    }

    /// And the converse: a halt that lifts while the form is open must not
    /// leave the user stuck. Continue is not hard-disabled for exactly this
    /// reason — the tap re-reads the route.
    func testAHaltThatLiftsWhileTheFormIsOpenUnblocksTheTap() async {
        let (viewModel, source) = await loadedViewModel(inbounds: [Self.makeInbound(halted: true)])
        viewModel.amountField.value = "1"
        XCTAssertNotNil(viewModel.routeMessage)

        source.inbounds = [Self.makeInbound(address: Self.inboundB)]

        let builder = await viewModel.prepareTransactionBuilder() as? SwitchTransactionBuilder
        XCTAssertEqual(builder?.inboundAddress, Self.inboundB)
        XCTAssertNil(viewModel.routeMessage)
    }

    // MARK: - Routes we cannot read

    /// `fetchThorchainInboundAddress` is fail-soft and answers with an empty
    /// list on a transport or decode failure, so an empty list means "we do not
    /// know" — never "not halted". The form fails closed AND says why.
    func testAnUnreadableRouteFailsClosedWithAMessage() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [])

        XCTAssertEqual(viewModel.routeState, .unavailable)
        XCTAssertEqual(viewModel.routeMessage, "switchRouteUnavailable".localized)

        viewModel.amountField.value = "1"
        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder)
    }

    /// A vault row with no address is as unusable as no row at all — signing it
    /// would broadcast to an empty recipient.
    func testAnEmptyInboundAddressFailsClosed() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [Self.makeInbound(address: "")])

        XCTAssertEqual(viewModel.routeState, .unavailable)
        viewModel.amountField.value = "1"
        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder)
    }

    func testAChainTHORChainDoesNotListIsSurfacedAsUnsupported() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [Self.makeInbound(chain: "BTC")])

        XCTAssertEqual(viewModel.routeState, .unsupported(chain: "GAIA"))
        XCTAssertEqual(viewModel.routeMessage, String(format: "inboundAddressNotFound".localized, "GAIA"))

        viewModel.amountField.value = "1"
        let builder = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(builder)
    }

    /// THORChain spells the chain in upper case; the match must not depend on
    /// it, or a casing change upstream would read as "unsupported".
    func testTheChainMatchIsCaseInsensitive() async {
        let (viewModel, _) = await loadedViewModel(inbounds: [Self.makeInbound(chain: "gaia")])
        XCTAssertEqual(viewModel.routeState, .available(inboundAddress: Self.inboundA))
    }

    // MARK: - Concurrency

    /// A load probe that answers after the tap's read must not overwrite the
    /// newer answer — cancellation cannot stop a response that has already
    /// resolved, so the generation stamp is the enforcement.
    func testAStaleLoadProbeDoesNotOverwriteTheTapsAnswer() async {
        let (viewModel, source) = makeViewModel()
        source.gatedChains.insert("GAIA")
        viewModel.onLoad()
        await waitFor("the load probe to park") { source.isParked("GAIA") }

        viewModel.thorAddressViewModel.field.value = Self.thorTarget
        viewModel.amountField.value = "1"

        // The tap's own read is not gated: only the parked first request is.
        source.gatedChains.remove("GAIA")
        source.inbounds = [Self.makeInbound(address: Self.inboundB)]
        let builder = await viewModel.prepareTransactionBuilder() as? SwitchTransactionBuilder
        XCTAssertEqual(builder?.inboundAddress, Self.inboundB)

        source.release("GAIA")
        await waitFor("the stale response to finish") { source.completedCount >= 2 }
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.routeState, .available(inboundAddress: Self.inboundB))
    }
}

/// Inbound-address source whose responses can be parked, so a test can make the
/// load-time probe answer after the Continue-tap read.
private final class StubInboundSource: ThorchainInboundSource, @unchecked Sendable {
    var inbounds: [InboundAddress] = []
    var gatedChains: Set<String> = []

    private var parked: [String: CheckedContinuation<Void, Never>] = [:]
    private var bypassCalls: [Bool] = []
    private var completed: Int = 0
    private let lock = NSLock()

    /// One entry per read, in order, recording whether it bypassed the cache.
    var bypassCacheCalls: [Bool] {
        lock.withLock { bypassCalls }
    }

    var completedCount: Int {
        lock.withLock { completed }
    }

    func isParked(_ chain: String) -> Bool {
        lock.withLock { parked[chain.uppercased()] != nil }
    }

    func release(_ chain: String) {
        let key = chain.uppercased()
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            gatedChains.remove(key)
            return parked.removeValue(forKey: key)
        }
        continuation?.resume()
    }

    func fetchThorchainInboundAddress(bypassCache: Bool) async -> [InboundAddress] {
        // Snapshot at entry: a parked read has to answer with what was current
        // when it started, or a stale response and a fresh one would agree by
        // construction and the generation guard would go untested.
        let (gate, snapshot): (String?, [InboundAddress]) = lock.withLock {
            bypassCalls.append(bypassCache)
            return (gatedChains.first, inbounds)
        }

        if let gate {
            await withCheckedContinuation { continuation in
                lock.withLock { parked[gate] = continuation }
            }
        }

        lock.withLock { completed += 1 }
        return snapshot
    }
}
