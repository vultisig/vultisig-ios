//
//  SendFeeEstimateTests.swift
//  VultisigAppTests
//
//  The amount step's fee estimate is display only: it must never change what
//  validation reads or what `makeTransaction()` hands to the review.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendFeeEstimateTests: XCTestCase {

    private let quotedFee = SendInteractorFeeResult(
        fee: BigInt(42_000_000_000_000),
        gas: BigInt(2_000_000_000),
        gasLimit: BigInt(21_000)
    )

    private func makeETHForm(interactor: MockSendInteractor) -> SendDetailsViewModel {
        let eth = SendFormFixture.makeETH()
        return SendFormFixture.make(
            coin: eth,
            vault: SendFormFixture.makeVault(coins: [eth]),
            interactor: interactor
        ) { vm in
            vm.toAddress = "0xdead"
            vm.amount = "0.5"
        }
    }

    func testEstimateLeavesTheHandOffTransactionUnchanged() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { [quotedFee] _ in quotedFee }
        let vm = makeETHForm(interactor: interactor)
        let before = try vm.makeTransaction()

        await vm.estimateFee()

        let after = try vm.makeTransaction()
        XCTAssertEqual(after.gas, before.gas)
        XCTAssertEqual(after.fee, before.fee)
        XCTAssertEqual(after.estimatedGasLimit, before.estimatedGasLimit)
        XCTAssertEqual(after.amount, before.amount)
        // The estimate ran and reads as the review would render this quote.
        let reviewed = before.with(gas: quotedFee.gas, fee: quotedFee.fee)
        XCTAssertEqual(vm.feeEstimate?.crypto, reviewed.gasInReadable)
        XCTAssertEqual(vm.feeEstimate?.fiat, CryptoAmountFormatter.feesInReadable(tx: reviewed))
    }

    func testFailedEstimateClearsTheValueAndRaisesNoError() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { [quotedFee] _ in quotedFee }
        let vm = makeETHForm(interactor: interactor)
        await vm.estimateFee()
        XCTAssertNotNil(vm.feeEstimate)

        interactor.calculateEVMFeeStub = { _ in throw URLError(.timedOut) }
        vm.amount = "0.6"
        let before = try vm.makeTransaction()

        await vm.estimateFee()

        XCTAssertNil(vm.feeEstimate)
        XCTAssertFalse(vm.isEstimatingFee)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.showAlert)
        XCTAssertFalse(vm.showAmountAlert)
        XCTAssertTrue(vm.isValidForm)
        XCTAssertEqual(vm.amountValidation, .valid)
        let after = try vm.makeTransaction()
        XCTAssertEqual(after.gas, before.gas)
        XCTAssertEqual(after.fee, before.fee)
        XCTAssertEqual(after.amount, before.amount)
        XCTAssertEqual(after.sendMaxAmount, before.sendMaxAmount)
    }

    func testEstimateForAnAssetLeftDuringTheAwaitIsNotApplied() async {
        let interactor = MockSendInteractor()
        let vm = makeETHForm(interactor: interactor)
        let eth = vm.coin
        let usdc = SendFormFixture.makeUSDC()
        interactor.calculateEVMFeeStub = { [quotedFee] _ in
            vm.coin = usdc
            return quotedFee
        }

        await vm.estimateFee()
        // Back on the asset the request was priced for, so only the post-await
        // guard can have kept the result out.
        vm.coin = eth

        XCTAssertNil(vm.feeEstimate)
        XCTAssertFalse(vm.isEstimatingFee)
    }

    func testUTXOFormIsNotEstimated() async throws {
        let interactor = MockSendInteractor()
        let btc = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(
            coin: btc,
            vault: SendFormFixture.makeVault(coins: [btc]),
            interactor: interactor
        ) { vm in
            vm.toAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
            vm.amount = "0.001"
        }
        _ = try vm.makeTransaction()

        await vm.estimateFee()

        XCTAssertTrue(interactor.fetchChainSpecificCalls.isEmpty)
        XCTAssertTrue(interactor.calculatePlanFeeCalls.isEmpty)
        XCTAssertTrue(interactor.calculateMaxSendPlanCalls.isEmpty)
        XCTAssertTrue(interactor.calculateEVMFeeCalls.isEmpty)
        XCTAssertNil(vm.feeEstimate)
        XCTAssertFalse(vm.isEstimatingFee)
    }
}
