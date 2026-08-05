//
//  SendGasLimitAssetBindingTests.swift
//  VultisigAppTests
//
//  A pinned gas limit belongs to the asset it was sized for.
//
//  The coin picker writes `viewModel.coin` directly and no view is responsible
//  for clearing the gas sheet's override, so a limit pinned for one asset used
//  to survive a switch and then price the next transaction verbatim —
//  `BlockChainService` honours a custom limit exactly, by design. Too low is
//  the dangerous direction: the transaction runs out of gas on-chain, which
//  burns the fee and delivers nothing.
//
//  The stamp is the asset rather than the chain (which is all a byte-fee rate
//  needs) because a gas limit prices one specific call: a native transfer is
//  sized at 23,000 units where an ERC20 transfer is sized at 120,000, on the
//  very same chain. `estimatedGasLimit` carries the same stamp — `gasLimit`
//  falls back to it, and the gas sheet re-pins whatever it displays.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendGasLimitAssetBindingTests: XCTestCase {

    // MARK: - Visibility of the pin

    func testPinnedLimitAppliesOnTheAssetItWasSetFor() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(500_000)

        XCTAssertEqual(vm.customGasLimit, BigInt(500_000))
        XCTAssertEqual(vm.gasLimit, BigInt(500_000))
    }

    func testPinnedLimitIsDroppedAfterSwitchingChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(500_000)

        vm.coin = SendFormFixture.makeCoin(.arbitrum, ticker: "ARB", decimals: 18, isNative: true)

        XCTAssertNil(vm.customGasLimit,
                     "a limit pinned for an Ethereum send must not size an Arbitrum one")
    }

    /// The case a chain-only stamp would miss, and the reason this one is
    /// keyed on the asset.
    func testPinnedLimitIsDroppedAfterSwitchingTokenOnTheSameChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(23_000)

        vm.coin = SendFormFixture.makeUSDC()

        XCTAssertNil(vm.customGasLimit,
                     "a native-transfer limit must not size an ERC20 transfer on the same chain")
    }

    func testPinnedLimitReturnsWhenSwitchingBack() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        vm.customGasLimit = BigInt(500_000)

        vm.coin = SendFormFixture.makeUSDC()
        XCTAssertNil(vm.customGasLimit)

        vm.coin = eth
        XCTAssertEqual(vm.customGasLimit, BigInt(500_000),
                       "returning to the asset the limit was sized for restores it")
    }

    func testRepinningOnTheNewAssetStampsThatAsset() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(23_000)

        vm.coin = SendFormFixture.makeUSDC()
        vm.customGasLimit = BigInt(150_000)

        XCTAssertEqual(vm.customGasLimit, BigInt(150_000))

        vm.coin = SendFormFixture.makeETH()
        XCTAssertNil(vm.customGasLimit, "the limit now belongs to USDC, not ETH")
    }

    func testClearingTheLimitAlsoClearsItsStamp() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        vm.customGasLimit = BigInt(500_000)
        vm.customGasLimit = nil

        vm.coin = eth
        XCTAssertNil(vm.customGasLimit)
    }

    // MARK: - What the form falls back to after a switch

    func testGasLimitFallsBackToTheNewAssetsDefault() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(500_000)

        vm.coin = SendFormFixture.makeUSDC()

        XCTAssertEqual(vm.gasLimit, BigInt(EVMHelper.defaultERC20TransferGasUnit),
                       "with the foreign pin gone the ERC20 default is the floor, not the pinned number")
    }

    /// `estimatedGasLimit` is `gasLimit`'s fallback, `BlockChainService` treats
    /// the requested limit as a floor, and the gas sheet re-pins what it shows
    /// — so a stale estimate would put the old asset's number back in front of
    /// the user, one Save away from becoming an exact custom limit.
    func testStaleEstimateIsDroppedAfterSwitchingAsset() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.estimatedGasLimit = BigInt(23_000)

        vm.coin = SendFormFixture.makeUSDC()

        XCTAssertNil(vm.estimatedGasLimit)
        XCTAssertEqual(vm.gasLimit, BigInt(EVMHelper.defaultERC20TransferGasUnit))
    }

    // MARK: - The paths a stale limit could still reach signing through

    /// The hand-off is the last point the stale limit could reach the signer.
    func testHandOffTransactionDoesNotCarryAForeignAssetLimit() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.customGasLimit = BigInt(23_000)
        vm.estimatedGasLimit = BigInt(23_000)

        vm.coin = SendFormFixture.makeUSDC()
        vm.toAddress = "0xdeadbeef"
        vm.amount = "100"

        let tx = try vm.makeTransaction()
        XCTAssertNil(tx.customGasLimit,
                     "the signed transaction must not size a USDC transfer at ETH's limit")
        XCTAssertNil(tx.estimatedGasLimit)
        XCTAssertEqual(tx.gasLimit, BigInt(EVMHelper.defaultERC20TransferGasUnit))
    }

    func testFeeRequestDoesNotCarryAForeignAssetLimit() async throws {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.customGasLimit = BigInt(23_000)

        vm.coin = SendFormFixture.makeCoin(.arbitrum, ticker: "ARB", decimals: 18, isNative: true,
                                           rawBalance: "1000000000000000000")
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // Unwrap first: an absent request would satisfy the nil assertion below
        // for the wrong reason — the refine never having run at all.
        let request = try XCTUnwrap(interactor.calculateEVMFeeCalls.last?.request,
                                    "the refine must have asked for a fee, or there is no request to inspect")
        XCTAssertNil(request.customGasLimit,
                     "the fee request must not carry a limit pinned for another asset")
    }

    /// The race the stamp alone does not close: a refine asks about one asset,
    /// the user switches while it is in flight, and the result lands — stamping
    /// the *new* asset with the *old* asset's number.
    func testInFlightRefineDoesNotStampTheNewAsset() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        let usdc = SendFormFixture.makeUSDC()

        interactor.calculateEVMFeeStub = { _ in
            // Stand in for the user tapping the coin picker while the fetch is
            // outstanding.
            vm.coin = usdc
            return SendInteractorFeeResult(fee: BigInt(1_000), gas: BigInt(1), gasLimit: BigInt(23_000))
        }

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertNil(vm.estimatedGasLimit,
                     "an ETH estimate must not be stamped onto the USDC the form has moved to")
        XCTAssertEqual(vm.gasLimit, BigInt(EVMHelper.defaultERC20TransferGasUnit))
    }

    /// The narrower window on the same race: the switch happens after
    /// `setMaxAmount()` returns but before the scheduled task body runs, so the
    /// task has not read anything yet. It must still refine the asset the user
    /// tapped Max on — which it is no longer on — rather than adopting the new
    /// one and quietly turning the switch into a max send of it.
    func testRefineDoesNotAdoptAnAssetSwitchedToBeforeItStarts() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(1_000), gas: BigInt(7), gasLimit: BigInt(60_000))
        }

        vm.setMaxAmount(percentage: 100)
        // No await in between: the picker gets its main-actor turn before the
        // task body's first line, which is the window this covers.
        vm.coin = SendFormFixture.makeCoin(.arbitrum, ticker: "ARB", decimals: 18, isNative: true,
                                           rawBalance: "5000000000000000000")

        await vm.feeRefineTask?.value

        XCTAssertTrue(interactor.calculateEVMFeeCalls.isEmpty,
                      "a refine that has lost its asset must stand down, not re-aim at the new one")
        XCTAssertNil(vm.estimatedGasLimit)
        XCTAssertEqual(vm.gas, .zero)
        XCTAssertEqual(vm.fee, .zero)
        XCTAssertFalse(vm.isCalculatingFee,
                       "standing down must still take the calculating indicator down — nothing else will")
    }

    /// The refresh path carries the same guard. Nothing in the app calls it
    /// today — it is reached only from here — so this test is what holds the
    /// guard in place for whenever the form starts refreshing its fee again.
    func testLoadGasInfoDropsAResultForAnAssetTheFormHasLeft() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        let usdc = SendFormFixture.makeUSDC()

        interactor.calculateEVMFeeStub = { _ in
            vm.coin = usdc
            return SendInteractorFeeResult(fee: BigInt(1_000), gas: BigInt(7), gasLimit: BigInt(23_000))
        }

        await vm.loadGasInfo()

        XCTAssertNil(vm.estimatedGasLimit)
        XCTAssertEqual(vm.gas, .zero,
                       "figures fetched for the asset the form has left must not be shown against the new one")
        XCTAssertEqual(vm.fee, .zero)
    }
}
