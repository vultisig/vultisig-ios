//
//  SendByteFeeChainBindingTests.swift
//  VultisigAppTests
//
//  A pinned sat/vB rate belongs to the chain it was pinned for.
//
//  The coin picker writes `viewModel.coin` directly and no view is responsible
//  for clearing the gas sheet's override, so a rate set for BTC used to survive
//  a switch to LTC or DOGE. That was inert while nothing consumed the value;
//  once the send path started honouring it, a BTC rate would price a DOGE
//  transaction — chains whose per-byte rates differ by four orders of magnitude.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendByteFeeChainBindingTests: XCTestCase {

    func testPinnedRateAppliesOnTheChainItWasSetFor() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.customByteFee = BigInt(300)

        XCTAssertEqual(vm.customByteFee, BigInt(300))
    }

    func testPinnedRateIsDroppedAfterSwitchingChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.customByteFee = BigInt(300)

        vm.coin = SendFormFixture.makeCoin(.dogecoin, ticker: "DOGE", decimals: 8, isNative: true,
                                           rawBalance: "100000000000")

        XCTAssertNil(vm.customByteFee,
                     "a BTC sat/vB rate must not price a DOGE send — DOGE quotes ~125,000 where BTC quotes ~20")
    }

    func testPinnedRateReturnsWhenSwitchingBack() {
        let btc = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(coin: btc)
        vm.customByteFee = BigInt(300)

        vm.coin = SendFormFixture.makeCoin(.litecoin, ticker: "LTC", decimals: 8, isNative: true)
        XCTAssertNil(vm.customByteFee)

        vm.coin = btc
        XCTAssertEqual(vm.customByteFee, BigInt(300),
                       "returning to the chain the rate was set for restores it")
    }

    func testRepinningOnTheNewChainStampsThatChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.customByteFee = BigInt(300)

        let ltc = SendFormFixture.makeCoin(.litecoin, ticker: "LTC", decimals: 8, isNative: true)
        vm.coin = ltc
        vm.customByteFee = BigInt(1_200)

        XCTAssertEqual(vm.customByteFee, BigInt(1_200))

        vm.coin = SendFormFixture.makeBTC()
        XCTAssertNil(vm.customByteFee, "the rate now belongs to LTC, not BTC")
    }

    func testClearingTheRateAlsoClearsItsChainStamp() {
        let btc = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(coin: btc)
        vm.customByteFee = BigInt(300)
        vm.customByteFee = nil

        vm.coin = btc
        XCTAssertNil(vm.customByteFee)
    }

    /// The hand-off is the last point the stale rate could still reach signing.
    func testHandOffTransactionDoesNotCarryAForeignChainRate() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.customByteFee = BigInt(300)

        vm.coin = SendFormFixture.makeCoin(.litecoin, ticker: "LTC", decimals: 8, isNative: true,
                                           rawBalance: "100000000")
        vm.toAddress = "ltc1qtest"
        vm.amount = "0.5"

        let tx = try vm.makeTransaction()
        XCTAssertNil(tx.customByteFee,
                     "the signed transaction must not price LTC at a rate pinned for BTC")
    }

    func testChainSpecificRequestDropsAForeignChainRate() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC(), interactor: interactor)
        vm.customByteFee = BigInt(300)

        vm.coin = SendFormFixture.makeCoin(.litecoin, ticker: "LTC", decimals: 8, isNative: true,
                                           rawBalance: "100000000")
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertNil(interactor.calculateMaxSendPlanCalls.last?.customByteFee,
                     "the fee request must not carry a rate pinned for another chain")
    }
}
