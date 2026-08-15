//
//  RebondTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate for the THORChain node REBOND form. `transactionBuilder`
//  returning nil is the enforcement — `FormScreen` does not disable Continue
//  on `validForm` — so every rejection case is asserted through the builder,
//  not through a flag. Includes the case the legacy sub-model got wrong: the
//  "REBOND requires RUNE" rule was written to a label its validity gate never
//  read, so a non-RUNE asset only looked blocked.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class RebondTransactionViewModelTests: XCTestCase {

    private static let currentNode = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"
    private static let newNode = "thor1pe0pspu4ep85gxr5h9l6k49g024vemtr80hg4c"
    private static let mayaNode = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"

    private func makeViewModel(
        coin: Coin = FunctionCallFixture.makeRUNE(),
        initialNodeAddress: String? = nil
    ) -> RebondTransactionViewModel {
        RebondTransactionViewModel(
            coin: coin,
            vault: FunctionCallFixture.makeVault(coins: [coin]),
            initialNodeAddress: initialNodeAddress
        )
    }

    /// `setupForm()` publishes validity on the main run loop, so the flag
    /// settles a turn after the value is written.
    private func awaitValidForm(_ viewModel: RebondTransactionViewModel, is expected: Bool) async {
        guard viewModel.validForm != expected else { return }
        let settled = XCTestExpectation(description: "validForm becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$validForm
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    /// Gives the form's validity pipeline a run-loop turn without asserting a
    /// transition — for the cases where the expected result is the same value
    /// the flag already held.
    private func settle() async {
        let turned = XCTestExpectation(description: "run loop turn")
        RunLoop.main.perform { turned.fulfill() }
        await fulfillment(of: [turned], timeout: 2)
    }

    private func fillValidAddresses(_ viewModel: RebondTransactionViewModel) {
        viewModel.nodeViewModel.field.value = Self.currentNode
        viewModel.newAddressViewModel.field.value = Self.newNode
    }

    // MARK: - Empty

    func testPristineFormStartsEmptyAndBlocked() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.nodeViewModel.field.value, "")
        XCTAssertEqual(viewModel.newAddressViewModel.field.value, "")
        XCTAssertEqual(viewModel.amountField.value, "")
        XCTAssertFalse(viewModel.validForm)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testEmptyAddressesBlockTheBuilder() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder, "An empty form must not produce a REBOND memo")
        XCTAssertNotNil(viewModel.nodeViewModel.field.error)
        XCTAssertNotNil(viewModel.newAddressViewModel.field.error)
    }

    func testMissingNewNodeAddressBlocksTheBuilder() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        viewModel.nodeViewModel.field.value = Self.currentNode
        await settle()

        XCTAssertFalse(viewModel.validForm)
        XCTAssertNil(viewModel.transactionBuilder, "REBOND needs the memo's second address")
    }

    // MARK: - Invalid addresses

    func testGarbageCurrentNodeAddressBlocksTheBuilder() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.nodeViewModel.field.value = "not-an-address"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// Tighter than the legacy sub-model, which accepted any THOR / Maya / TON
    /// address on either field. A Maya address in a THORChain REBOND memo names
    /// an account that chain has never heard of.
    func testMayaNodeAddressIsRejectedOnThorchain() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.newAddressViewModel.field.value = Self.mayaNode
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Valid, both memo shapes

    func testWholeBondProducesTheBuilderWithNoAmountSegment() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        let builder = viewModel.transactionBuilder as? RebondTransactionBuilder
        XCTAssertEqual(builder?.nodeAddress, Self.currentNode)
        XCTAssertEqual(builder?.newAddress, Self.newNode)
        XCTAssertEqual(builder?.rebondAmount, 0)
        XCTAssertEqual(builder?.memo, "REBOND:\(Self.currentNode):\(Self.newNode)")
        XCTAssertEqual(builder?.amount, "0")
    }

    func testPartialBondProducesTheBuilderWithTheAmountSegment() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        viewModel.amountField.value = "100"
        await awaitValidForm(viewModel, is: true)

        let builder = viewModel.transactionBuilder as? RebondTransactionBuilder
        XCTAssertEqual(builder?.rebondAmount, 100)
        XCTAssertEqual(builder?.memo, "REBOND:\(Self.currentNode):\(Self.newNode):10000000000")
        XCTAssertEqual(builder?.amount, "0", "The amount rides the memo, never the transaction")
    }

    // MARK: - Amount validation

    /// Legacy treated a typed `0` as "move the whole bond" — the same shape a
    /// user gets by leaving the field empty, but reached by typing a number
    /// that reads as "none".
    func testZeroAmountIsRejected() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.amountField.value = "0"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testNonNumericAmountIsRejected() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.amountField.value = "not-a-number"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// Below one base unit the 1e8 conversion truncates to zero, which would
    /// put a `:0` segment on the memo and rebond nothing.
    func testAmountBelowOneBaseUnitIsRejected() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.amountField.value = "0.000000005"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// The aggregate `validForm` is republished a run-loop turn late, so a
    /// submit in the same turn as the edit would otherwise read the *previous*
    /// answer — here, building the whole-bond memo from an amount the user just
    /// set to `0`. The builder has to reject it without waiting.
    func testInvalidatingTheAmountBlocksTheBuilderInTheSameRunLoopTurn() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        viewModel.amountField.value = "100"
        await awaitValidForm(viewModel, is: true)

        viewModel.amountField.value = "0"
        XCTAssertTrue(viewModel.validForm, "Precondition: the aggregate has not settled yet")
        XCTAssertNil(viewModel.transactionBuilder, "A same-turn edit must not submit on a stale aggregate")
    }

    /// The same window on an address: an address cleared and submitted
    /// in one turn must not ride the previous "valid".
    func testClearingAnAddressBlocksTheBuilderInTheSameRunLoopTurn() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.newAddressViewModel.field.value = ""
        XCTAssertTrue(viewModel.validForm, "Precondition: the aggregate has not settled yet")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// The mirror window, which reading the stale aggregate would get wrong in
    /// the other direction: a form completed and submitted in one turn must not
    /// have its first Continue tap silently swallowed.
    func testCompletingTheFormBuildsInTheSameRunLoopTurn() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        fillValidAddresses(viewModel)
        XCTAssertFalse(viewModel.validForm, "Precondition: the aggregate has not settled yet")

        let builder = viewModel.transactionBuilder as? RebondTransactionBuilder
        XCTAssertEqual(builder?.memo, "REBOND:\(Self.currentNode):\(Self.newNode)")
    }

    /// One base unit is the smallest amount that survives the conversion.
    func testSmallestRepresentableAmountIsAccepted() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        viewModel.amountField.value = "0.00000001"
        await awaitValidForm(viewModel, is: true)

        let builder = viewModel.transactionBuilder as? RebondTransactionBuilder
        XCTAssertEqual(builder?.memo, "REBOND:\(Self.currentNode):\(Self.newNode):1")
    }

    // MARK: - The RUNE guard (the legacy defect)

    /// Legacy `validate(against:)` wrote this message to `customErrorMessage`
    /// while `isTheFormValid` looked only at the addresses, so a TCY selection
    /// showed the warning and submitted anyway. The rule is a form validator
    /// now: no address the user can type opens the gate.
    func testNonRuneAssetBlocksTheBuilderEvenWithValidAddresses() async {
        let viewModel = makeViewModel(coin: FunctionCallFixture.makeTCY())
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await settle()

        XCTAssertFalse(viewModel.validForm)
        XCTAssertNil(viewModel.transactionBuilder, "REBOND on a non-RUNE asset must not build")
        XCTAssertEqual(viewModel.nodeViewModel.field.error, "rebondRequiresRune".localized)
    }

    /// The control for the test above: the identical inputs on RUNE do build.
    func testRuneAssetWithTheSameInputsDoesBuild() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        XCTAssertNotNil(viewModel.transactionBuilder)
        XCTAssertNil(viewModel.nodeViewModel.field.error)
    }

    // MARK: - Gate re-closes

    func testClearingAValidAddressClosesTheGateAgain() async {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        fillValidAddresses(viewModel)
        await awaitValidForm(viewModel, is: true)

        viewModel.nodeViewModel.field.value = ""
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Pre-fill

    func testInitialNodeAddressPrefillsTheCurrentNodeField() async {
        let viewModel = makeViewModel(initialNodeAddress: Self.currentNode)
        viewModel.onLoad()
        await settle()

        XCTAssertEqual(viewModel.nodeViewModel.field.value, Self.currentNode)
        XCTAssertEqual(viewModel.newAddressViewModel.field.value, "", "Only the current node is ever known upfront")
        XCTAssertNil(viewModel.transactionBuilder, "The memo's second address is still missing")
    }

    func testEmptyInitialNodeAddressLeavesTheFieldPristine() async {
        let viewModel = makeViewModel(initialNodeAddress: "")
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        XCTAssertEqual(viewModel.nodeViewModel.field.value, "")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Address-result handling (carried from the legacy sub-model)

    func testAddressResultWritesEachNodeAddress() {
        let viewModel = makeViewModel()
        viewModel.nodeViewModel.handle(addressResult: AddressResult(address: Self.currentNode))
        viewModel.newAddressViewModel.handle(addressResult: AddressResult(address: Self.newNode))
        XCTAssertEqual(viewModel.nodeViewModel.field.value, Self.currentNode)
        XCTAssertEqual(viewModel.newAddressViewModel.field.value, Self.newNode)
    }

    func testNilAddressResultLeavesTheNodeAddressUnchanged() {
        let viewModel = makeViewModel()
        viewModel.nodeViewModel.field.value = Self.currentNode
        viewModel.nodeViewModel.handle(addressResult: nil)
        XCTAssertEqual(viewModel.nodeViewModel.field.value, Self.currentNode)
    }
}
