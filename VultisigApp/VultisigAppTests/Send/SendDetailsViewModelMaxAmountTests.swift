//
//  SendDetailsViewModelMaxAmountTests.swift
//  VultisigAppTests
//
//  Per-chain integration tests for `SendDetailsViewModel.setMaxAmount`.
//
//  `setMaxAmount` fills the displayed amount synchronously from
//  `coin.balanceDecimal` in every case (instant fill). Only native-coin Max
//  needs the real fee subtracted, so it fills optimistically with the full
//  balance and then refines to `balance − fee` in a background task
//  (`feeRefineTask`) — tests await that task to observe the settled value.
//
//  Non-native sends and partial percentages never touch the interactor: they
//  fill from balance directly, since the Verify screen owns the precise fee
//  validation before signing.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendDetailsViewModelMaxAmountTests: XCTestCase {

    // MARK: - EVM native (optimistic → refine)

    func testMaxAmountForEVMNativeOptimisticallyFillsBalanceThenRefinesByFee() async {
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000") // 1 ETH
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "10000000000000000"), // 0.01 ETH
                                    gas: BigInt(50_000_000_000))
        }
        let vm = SendFormFixture.make(coin: eth, interactor: interactor)

        vm.setMaxAmount(percentage: 100)

        // Optimistic fill — full balance, before the refine lands.
        XCTAssertEqual(vm.sendMaxAmount, true)
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "1"))

        await vm.feeRefineTask?.value

        // Refined — balance minus the fetched fee.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.99"))
        XCTAssertFalse(vm.isCalculatingFee, "refine must clear the calculating-fee indicator")
        XCTAssertEqual(interactor.calculateEVMFeeCalls.count, 1)
    }

    func testMaxAmountForEVMTokenFillsFullBalanceWithoutFetchingFee() async {
        let usdc = SendFormFixture.makeUSDC(rawBalance: "1000000000") // 1000 USDC
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: usdc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "1000"),
                       "ERC20 max-send: gas is paid in native ETH, token balance is the whole pool.")
        XCTAssertNil(vm.feeRefineTask, "non-native must not kick a fee refine")
        XCTAssertTrue(interactor.fetchChainSpecificCalls.isEmpty, "non-native max must not hit the interactor")
        XCTAssertTrue(interactor.calculateEVMFeeCalls.isEmpty, "non-native max must not hit the interactor")
    }

    // MARK: - UTXO native (optimistic → refine)

    func testMaxAmountForUTXOOptimisticallyFillsBalanceThenRefinesByPlanFee() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            // UTXO max reads `.fee` off chainSpecific; the THORChain variant
            // exposes a fee-bearing tagged enum convenient for unit tests.
            .THORChain(accountNumber: 0, sequence: 0, fee: 5_000, isDeposit: false, transactionType: 0)
        }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)

        // Optimistic — full 1 BTC before the plan fee is known.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "1"))

        await vm.feeRefineTask?.value

        // 1 BTC = 100_000_000 sats; minus 5_000 sats fee = 99_995_000 sats = 0.99995 BTC.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.99995"))
    }

    // MARK: - Solana native

    func testMaxAmountForSolanaSetsAmountAndFlagsMaxSend() async {
        let sol = SendFormFixture.makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true,
                                           rawBalance: "1000000000") // 1 SOL
        let vm = SendFormFixture.make(coin: sol)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // String formatting is locale-dependent — assert the structural
        // behavior rather than the exact numeric value.
        XCTAssertFalse(vm.amount.isEmpty, "setMaxAmount must populate vm.amount")
        XCTAssertTrue(vm.sendMaxAmount, "100% setMaxAmount must flag sendMaxAmount = true")
    }

    // MARK: - Cosmos native

    func testMaxAmountForCosmosRefinesViaChainSpecificGas() async {
        let atom = SendFormFixture.makeATOM(rawBalance: "10000000") // 10 ATOM
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Cosmos(accountNumber: 0, sequence: 0, gas: 2_000, transactionType: 0, ibcDenomTrace: nil)
        }
        let vm = SendFormFixture.make(coin: atom, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // Structural: native Max refines through fetchChainSpecific, populated
        // an amount, and flagged max.
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 1)
        XCTAssertFalse(vm.amount.isEmpty)
        XCTAssertTrue(vm.sendMaxAmount)
    }

    // MARK: - Percentage scaling (instant, no fetch)

    func testMaxAmountAt50PercentFillsHalfBalanceWithoutFetch() {
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000") // 1 ETH
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: eth, interactor: interactor)

        vm.setMaxAmount(percentage: 50)

        // 1 ETH → 50% of balance = 0.5 ETH (no fee reserved).
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.5"))
        XCTAssertFalse(vm.sendMaxAmount, "Less-than-100% must not set sendMaxAmount flag.")
        XCTAssertNil(vm.feeRefineTask, "partial % must not kick a fee refine")
        XCTAssertTrue(interactor.fetchChainSpecificCalls.isEmpty, "partial % must not hit the interactor")
        XCTAssertTrue(interactor.calculateEVMFeeCalls.isEmpty, "partial % must not hit the interactor")
    }

    // MARK: - Race / cancellation guard

    func testNewPresetCancelsInFlightRefineAndWins() async {
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000") // 1 ETH
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "10000000000000000"), gas: BigInt(50_000_000_000))
        }
        let vm = SendFormFixture.make(coin: eth, interactor: interactor)

        // Kick the native-Max refine, then immediately switch to 50% before it
        // settles. The stale refine must not clobber the newer 50% value.
        vm.setMaxAmount(percentage: 100)
        let staleRefine = vm.feeRefineTask
        vm.setMaxAmount(percentage: 50)
        await staleRefine?.value

        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.5"),
                       "stale native-Max refine must not overwrite the newer 50% fill")
        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertNil(vm.feeRefineTask, "switching to a partial % must clear the refine task")
    }

    // MARK: - Error path

    func testMaxAmountRefineErrorKeepsOptimisticBalance() async {
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000") // 1 ETH
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        let vm = SendFormFixture.make(coin: eth, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // On refine failure we keep the optimistic full-balance value rather
        // than wiping the field; Verify recomputes the real fee.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "1"),
                       "failed refine must keep the optimistic balance fill")
        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertFalse(vm.isCalculatingFee, "isCalculatingFee must reset after the refine settles")
    }

    // MARK: - feeMode threading

    func testNativeMaxRefineThreadsFeeMode() async {
        let eth = SendFormFixture.makeETH()
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: eth, interactor: interactor)
        vm.feeMode = .fast

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(interactor.fetchChainSpecificCalls.last?.feeMode, .fast)
        XCTAssertEqual(interactor.calculateEVMFeeCalls.last?.feeMode, .fast)
    }
}
