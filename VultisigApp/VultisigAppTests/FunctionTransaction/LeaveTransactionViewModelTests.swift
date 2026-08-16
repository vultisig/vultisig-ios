//
//  LeaveTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate for the node LEAVE form. `transactionBuilder` returning
//  nil is the enforcement — `FormScreen` does not disable Continue on
//  `validForm` — so every rejection case is asserted through the builder,
//  not through a flag. Carries over the form-validity and address-handling
//  assertions from the deleted `FunctionCallLeaveTests`.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class LeaveTransactionViewModelTests: XCTestCase {

    private static let thorNode = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"
    private static let mayaNode = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"

    private func makeThorViewModel(initialNodeAddress: String? = nil) -> LeaveTransactionViewModel {
        let coin = FunctionActionFixture.makeRUNE()
        return LeaveTransactionViewModel(
            coin: coin,
            vault: FunctionActionFixture.makeVault(coins: [coin]),
            initialNodeAddress: initialNodeAddress
        )
    }

    private func makeMayaViewModel(initialNodeAddress: String? = nil) -> LeaveTransactionViewModel {
        let coin = FunctionActionFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            address: FunctionActionFixture.mayaAddress
        )
        return LeaveTransactionViewModel(
            coin: coin,
            vault: FunctionActionFixture.makeVault(coins: [coin]),
            initialNodeAddress: initialNodeAddress
        )
    }

    /// `setupForm()` publishes validity on the main run loop, so the flag
    /// settles a turn after the value is written.
    private func awaitValidForm(_ viewModel: LeaveTransactionViewModel, is expected: Bool) async {
        guard viewModel.validForm != expected else { return }
        let settled = XCTestExpectation(description: "validForm becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$validForm
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    // MARK: - Empty

    func testPristineFormStartsEmptyAndBlocked() {
        let viewModel = makeThorViewModel()
        XCTAssertEqual(viewModel.addressViewModel.field.value, "")
        XCTAssertNil(viewModel.addressViewModel.field.error)
        XCTAssertFalse(viewModel.validForm)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testEmptyNodeAddressBlocksTheBuilder() async {
        let viewModel = makeThorViewModel()
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder, "An empty node address must not produce a LEAVE memo")
        XCTAssertNotNil(viewModel.addressViewModel.field.error, "The empty field must surface its error")
    }

    // MARK: - Invalid

    func testGarbageNodeAddressBlocksTheBuilder() async {
        let viewModel = makeThorViewModel()
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = "not-an-address"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// Tighter than the legacy sub-model, which accepted any THOR / Maya / TON
    /// address on either chain. A Maya node address in a THORChain LEAVE memo
    /// names a validator that chain has never heard of.
    func testMayaNodeAddressIsRejectedOnThorchain() async {
        let viewModel = makeThorViewModel()
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = Self.mayaNode
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Valid

    func testValidThorNodeAddressProducesTheBuilder() async {
        let viewModel = makeThorViewModel()
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = Self.thorNode
        await awaitValidForm(viewModel, is: true)

        let builder = viewModel.transactionBuilder as? LeaveTransactionBuilder
        XCTAssertEqual(builder?.nodeAddress, Self.thorNode)
        XCTAssertEqual(builder?.memo, "LEAVE:\(Self.thorNode)")
        XCTAssertEqual(builder?.amount, "0")
    }

    func testValidMayaNodeAddressProducesTheBuilder() async {
        let viewModel = makeMayaViewModel()
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = Self.mayaNode
        await awaitValidForm(viewModel, is: true)

        let builder = viewModel.transactionBuilder as? LeaveTransactionBuilder
        XCTAssertEqual(builder?.nodeAddress, Self.mayaNode)
        XCTAssertEqual(builder?.memo, "LEAVE:\(Self.mayaNode)")
        XCTAssertEqual(builder?.amount, "0")
    }

    func testClearingAValidAddressClosesTheGateAgain() async {
        let viewModel = makeThorViewModel()
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = Self.thorNode
        await awaitValidForm(viewModel, is: true)

        viewModel.addressViewModel.field.value = ""
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Pre-fill

    func testInitialNodeAddressPrefillsTheFieldAndOpensTheGate() async {
        let viewModel = makeThorViewModel(initialNodeAddress: Self.thorNode)
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: true)

        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.thorNode)
        XCTAssertEqual((viewModel.transactionBuilder as? LeaveTransactionBuilder)?.nodeAddress, Self.thorNode)
    }

    func testEmptyInitialNodeAddressLeavesTheFieldPristine() async {
        let viewModel = makeThorViewModel(initialNodeAddress: "")
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        XCTAssertEqual(viewModel.addressViewModel.field.value, "")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Address-result handling (carried from the legacy sub-model)

    func testAddressResultWritesTheNodeAddress() {
        let viewModel = makeThorViewModel()
        viewModel.addressViewModel.handle(addressResult: AddressResult(address: Self.thorNode))
        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.thorNode)
    }

    func testNilAddressResultLeavesTheNodeAddressUnchanged() {
        let viewModel = makeThorViewModel()
        viewModel.addressViewModel.field.value = Self.thorNode
        viewModel.addressViewModel.handle(addressResult: nil)
        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.thorNode)
    }
}
