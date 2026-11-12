//
//  SendStepNavigationTests.swift
//  VultisigAppTests
//
//  `SendDetailsViewModel` step rules: which step the form opens on, which
//  steps the header may jump to, and the state each step icon shows.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SendStepNavigationTests: XCTestCase {

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testAPreselectedCoinOpensOnAddressWithAssetComplete() {
        let vm = makeViewModel(hasPreselectedCoin: true)

        vm.onLoad()

        XCTAssertEqual(vm.selectedTab, .address)
        XCTAssertEqual(vm.stepState(for: .asset), .valid)
        XCTAssertEqual(vm.stepState(for: .address), .active)
        XCTAssertEqual(vm.stepState(for: .amount), .inactive)
    }

    func testNoPreselectedCoinOpensOnAssetWithLaterStepsLocked() {
        let vm = makeViewModel(hasPreselectedCoin: false)

        vm.onLoad()

        XCTAssertEqual(vm.selectedTab, .asset)
        XCTAssertEqual(vm.stepState(for: .asset), .active)
        XCTAssertEqual(vm.stepState(for: .address), .inactive)
        XCTAssertFalse(vm.canNavigate(to: .asset))
        XCTAssertFalse(vm.canNavigate(to: .address))
    }

    func testAmountIsReachableOnlyOnceAssetAndAddressAreComplete() {
        let vm = makeViewModel(hasPreselectedCoin: false)
        vm.onLoad()
        vm.addressSetupDone = true

        XCTAssertFalse(vm.canNavigate(to: .amount))

        vm.assetSetupDone = true
        vm.addressSetupDone = false

        XCTAssertTrue(vm.canNavigate(to: .address))
        XCTAssertFalse(vm.canNavigate(to: .amount))

        vm.addressSetupDone = true

        XCTAssertTrue(vm.canNavigate(to: .amount))
    }

    func testSelectingAmountBeforeTheAddressIsCompleteKeepsTheCurrentStep() {
        let vm = makeViewModel(hasPreselectedCoin: true)
        vm.onLoad()

        vm.onSelect(tab: .amount)

        XCTAssertFalse(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testContinueOnTheAssetStepNeedsTheCoinShownUnderTheChainFilter() {
        let vm = makeEthereumFormWithBitcoinInTheVault()

        XCTAssertTrue(vm.isCoinShownOnAssetStep)

        vm.assetFilter = .chain(.bitcoin)
        XCTAssertFalse(vm.isCoinShownOnAssetStep)

        vm.assetFilter = .chain(.ethereum)
        XCTAssertTrue(vm.isCoinShownOnAssetStep)
    }

    func testContinueOnTheAssetStepNeedsTheCoinShownUnderTheSearch() {
        let vm = makeEthereumFormWithBitcoinInTheVault()

        vm.assetSearchText = "btc"
        XCTAssertFalse(vm.isCoinShownOnAssetStep)

        // A search spans every chain, whatever chain is picked.
        vm.assetFilter = .chain(.bitcoin)
        vm.assetSearchText = " ETH "
        XCTAssertTrue(vm.isCoinShownOnAssetStep)
    }

    private func makeEthereumFormWithBitcoinInTheVault() -> SendDetailsViewModel {
        let eth = SendFormFixture.makeETH()
        let vm = SendDetailsViewModel(
            coin: eth,
            vault: SendFormFixture.makeVault(coins: [eth, SendFormFixture.makeBTC()]),
            hasPreselectedCoin: false,
            interactor: MockSendInteractor()
        )
        vm.onLoad()
        return vm
    }

    private func makeViewModel(hasPreselectedCoin: Bool) -> SendDetailsViewModel {
        SendDetailsViewModel(
            coin: SendFormFixture.makeETH(),
            vault: SendFormFixture.makeVault(),
            hasPreselectedCoin: hasPreselectedCoin,
            interactor: MockSendInteractor()
        )
    }
}
