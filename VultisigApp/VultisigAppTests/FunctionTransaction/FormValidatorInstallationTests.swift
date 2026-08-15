//
//  FormValidatorInstallationTests.swift
//  VultisigAppTests
//
//  Covers the shared `Form` stack's second source of change: validators that are
//  installed after the user has already typed. Balances, bonded amounts and pool
//  minimums all arrive asynchronously, and no keystroke follows them — so the
//  swap itself has to be what makes an out-of-range value invalid.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class FormValidatorInstallationTests: XCTestCase {

    /// A bech32 MayaChain address, so the node-address field passes its own
    /// validators and the LP-units rule is the only thing left to fail.
    private static let nodeAddress = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"
    private static let pool = "MAYA.CACAO"

    // MARK: - The shared stack

    /// Minimal `Form` conformer: what is under test is the protocol extension,
    /// not any one screen's view model.
    @MainActor
    private final class TestForm: ObservableObject, Form {
        @Published var validForm: Bool = false
        let field: FormField
        private(set) lazy var form: [FormField] = [field]
        var formCancellable: AnyCancellable?

        init(field: FormField) {
            self.field = field
        }
    }

    private func makeLPUnitsForm() -> TestForm {
        let field = FormField(
            label: "lpUnits",
            validators: [RequiredValidator(errorMessage: "emptyLPsField"), IntValidator()]
        )
        let form = TestForm(field: field)
        form.setupForm()
        return form
    }

    /// The regression: a stricter validator installed after the value is typed
    /// must flip `validForm` on its own. Nothing re-publishes the field's value
    /// behind an async balance, so a pipeline driven by `$value` alone keeps
    /// answering for the validators the form had before the swap — and
    /// `transactionBuilder` guards on exactly that flag.
    func testValidFormFollowsAValidatorInstalledAfterTyping() {
        let form = makeLPUnitsForm()

        form.field.value = "500"
        XCTAssertTrue(form.revalidate(), "500 units are acceptable to the validators installed while typing")

        // The available balance lands and narrows the rule. No keystroke follows.
        form.field.validators.append(LPUnitsValidator(availableUnits: "100"))

        XCTAssertFalse(
            form.validForm,
            "validForm must answer for the validators installed now, not the ones the form had while typing"
        )
    }

    /// The same swap must not invent a failure: a value inside the new ceiling
    /// stays valid, so the assertion above is about the ceiling and not about any
    /// validator mutation resetting the form.
    func testValidFormStaysTrueWhenTheInstalledValidatorIsSatisfied() {
        let form = makeLPUnitsForm()

        form.field.value = "50"
        XCTAssertTrue(form.revalidate())

        form.field.validators.append(LPUnitsValidator(availableUnits: "100"))

        XCTAssertTrue(form.validForm)
    }

    /// Replacing the validator set wholesale — how most screens install their
    /// balance-aware rules — has to publish as well as appending does.
    func testReplacingTheValidatorSetRepublishesValidForm() {
        let form = makeLPUnitsForm()

        form.field.value = "500"
        XCTAssertTrue(form.revalidate())

        form.field.validators = [
            RequiredValidator(errorMessage: "emptyLPsField"),
            IntValidator(),
            LPUnitsValidator(availableUnits: "100")
        ]

        XCTAssertFalse(form.validForm)
    }

    /// Validators are often installed *before* the pipeline is wired — the
    /// Kamino forms build theirs from an awaited vault probe and only then call
    /// `setupForm()`. A subject cannot replay those, so setup itself has to
    /// answer for them rather than leaving the flag until the run loop turns.
    func testSetupFormEstablishesValidFormFromValidatorsInstalledBeforeIt() {
        let field = FormField(
            label: "lpUnits",
            validators: [RequiredValidator(errorMessage: "emptyLPsField"), IntValidator()]
        )
        field.value = "50"
        field.validators.append(LPUnitsValidator(availableUnits: "100"))

        let form = TestForm(field: field)
        XCTAssertFalse(form.validForm, "the flag starts false")

        form.setupForm()

        XCTAssertTrue(form.validForm, "setup must answer for the validators already installed")
    }

    /// The keystroke path still works after the rewrite. It hops through
    /// `RunLoop.main` because `@Published` publishes from `willSet`, so
    /// validating inline would judge the outgoing value.
    func testTypingPublishesValidFormThroughTheRunLoop() async {
        let form = makeLPUnitsForm()

        form.field.value = "500"

        await waitForValidForm(form, equals: true)
        XCTAssertTrue(form.validForm)
    }

    /// `validateErrors()` is the Continue-tap path, and every caller reads
    /// `validForm` straight afterwards to decide whether to build a transaction.
    /// It must republish the flag rather than trust whatever the asynchronous
    /// pipeline last left there.
    func testValidateErrorsRepublishesValidFormForTheCurrentValidators() {
        let field = FormField(label: "lpUnits")
        let form = TestForm(field: field)
        // Deliberately no `setupForm()`: the tap has to stand on its own.
        field.value = "500"
        field.validators = [LPUnitsValidator(availableUnits: "100")]

        form.validateErrors()

        XCTAssertFalse(form.validForm)
        XCTAssertNotNil(field.error, "the tap also reveals the error on the offending field")
    }

    // MARK: - Maya bond: asset picked after the units are typed

    /// Type the LP units, then pick the asset. The picker is what installs
    /// `LPUnitsValidator`, so this ordering is the one that used to let an
    /// over-available bond through.
    func testMayaBondRejectsLPUnitsAboveAvailableWhenAssetPickedAfterTyping() {
        let viewModel = makeBondMayaViewModel()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.lpUnitsField.value = "500"
        XCTAssertTrue(viewModel.revalidate(), "the form is valid under the validators installed before the pick")

        viewModel.userLPPositions = [Self.pool: "100"]
        viewModel.selectedAsset = mayaAsset()
        viewModel.onAssetSelected(mayaAsset())

        XCTAssertFalse(viewModel.validForm, "500 units against 100 available must invalidate the form")
        XCTAssertNil(viewModel.transactionBuilder, "an over-available bond must not reach the signer")
    }

    /// The control: the same ordering with units inside the available amount
    /// still builds, so the `nil` above is the LP ceiling and not a form the test
    /// simply left unfinished.
    func testMayaBondAcceptsLPUnitsWithinAvailableWhenAssetPickedAfterTyping() {
        let viewModel = makeBondMayaViewModel()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.lpUnitsField.value = "50"
        XCTAssertTrue(viewModel.revalidate())

        viewModel.userLPPositions = [Self.pool: "100"]
        viewModel.selectedAsset = mayaAsset()
        viewModel.onAssetSelected(mayaAsset())

        XCTAssertTrue(viewModel.validForm)
        let builder = viewModel.transactionBuilder as? BondMayaTransactionBuilder
        XCTAssertEqual(builder?.lpUnits, 50)
        XCTAssertEqual(builder?.selectedAsset, Self.pool)
        XCTAssertEqual(builder?.nodeAddress, Self.nodeAddress)
    }

    // MARK: - Retain cycle

    /// The bond form's operator-fee rule reads another field, so it is written as
    /// a closure over the view model. Captured strongly it is a cycle the view
    /// model can never break: the view model owns the field, the field owns the
    /// validator, the validator owns the view model.
    func testBondViewModelDeallocatesAfterInstallingItsClosureValidator() {
        weak var weakViewModel: BondTransactionViewModel?

        autoreleasepool {
            let viewModel = BondTransactionViewModel(
                coin: makeCoin(chain: .thorChain, ticker: "RUNE", decimals: 8),
                vault: .example,
                initialBondAddress: nil
            )
            viewModel.onLoad()
            weakViewModel = viewModel
        }

        XCTAssertNil(weakViewModel, "the operator-fee validator must not retain the view model")
    }

    // MARK: - Helpers

    private func makeBondMayaViewModel() -> BondMayaTransactionViewModel {
        let viewModel = BondMayaTransactionViewModel(
            coin: makeCoin(chain: .mayaChain, ticker: "CACAO", decimals: 10),
            vault: .example,
            initialBondAddress: nil
        )
        // `onLoad()` also fires the Maya API calls that seed `userLPPositions`
        // and the asset list. This seeds both directly and installs the same form
        // wiring, so the test never touches the network.
        viewModel.setupForm()
        viewModel.lpUnitsField.validators = [
            RequiredValidator(errorMessage: "emptyLPsField"),
            IntValidator()
        ]
        return viewModel
    }

    private func makeCoinMeta(chain: Chain, ticker: String, decimals: Int) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
    }

    private func makeCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        Coin(
            asset: makeCoinMeta(chain: chain, ticker: ticker, decimals: decimals),
            address: Self.nodeAddress,
            hexPublicKey: ""
        )
    }

    private func mayaAsset() -> THORChainAsset {
        THORChainAsset(
            thorchainAsset: Self.pool,
            asset: makeCoinMeta(chain: .mayaChain, ticker: "CACAO", decimals: 10)
        )
    }

    /// Polls until the asynchronous value branch has delivered, giving the main
    /// run loop the turns it needs between checks.
    private func waitForValidForm(_ form: some Form, equals expected: Bool) async {
        for _ in 0..<200 {
            if form.validForm == expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
