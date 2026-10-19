//
//  SendAddressAutoAdvanceTests.swift
//  VultisigAppTests
//
//  `SendDetailsViewModel.handleToAddressChange` / `handleAddressResolution`: a
//  valid recipient that a longer valid address could still extend is marked
//  set without leaving the Address step.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SendAddressAutoAdvanceTests: XCTestCase {

    private static let nearImplicit = "eaacfd92874d932c636aeceb051566762b9bf8b8791f267eacd96ead4832a4f1"
    /// An on-curve key whose 43-character prefix also decodes to an on-curve key.
    private static let solanaAddress = "GwjcJ4pANQvpGsSJhtPQLcrwHedLTiMzneh9B6EQrQxV"

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

    func testATypedNearNamedAccountStaysOnTheAddressStep() {
        let vm = makeViewModel(.near, ticker: "NEAR", decimals: 24, address: "al")

        vm.handleToAddressChange()

        XCTAssertTrue(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testContinueStillMovesANamedAccountOnToAmount() {
        let vm = makeViewModel(.near, ticker: "NEAR", decimals: 24, address: "alice.near")
        vm.handleToAddressChange()

        vm.onSelect(tab: .amount)

        XCTAssertEqual(vm.selectedTab, .amount)
    }

    func testExtendingAValidNameIntoAnInvalidOneBlocksAmountUntilResolved() {
        let vm = makeViewModel(.near, ticker: "NEAR", decimals: 24, address: "al")
        vm.handleToAddressChange()

        vm.toAddress = "al."
        vm.handleToAddressChange()
        vm.onSelect(tab: .amount)

        XCTAssertFalse(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testANearImplicitAccountMovesOnToAmount() {
        let vm = makeViewModel(.near, ticker: "NEAR", decimals: 24, address: Self.nearImplicit)

        vm.handleToAddressChange()

        XCTAssertEqual(vm.selectedTab, .amount)
    }

    func testASolanaAddressShortOfTheMaximumStaysOnTheAddressStep() {
        let vm = makeViewModel(.solana, ticker: "SOL", decimals: 9, address: String(Self.solanaAddress.dropLast()))

        vm.handleToAddressChange()

        XCTAssertTrue(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testAFullLengthSolanaAddressMovesOnToAmount() {
        let vm = makeViewModel(.solana, ticker: "SOL", decimals: 9, address: Self.solanaAddress)

        vm.handleToAddressChange()

        XCTAssertEqual(vm.selectedTab, .amount)
    }

    func testAChainWithoutPrefixValidAddressesMovesOnToAmount() {
        let vm = makeViewModel(.ethereum, ticker: "ETH", decimals: 18, address: "0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF")

        vm.handleToAddressChange()

        XCTAssertEqual(vm.selectedTab, .amount)
    }

    func testAResolvedNearNamedAccountStaysOnTheAddressStep() {
        let vm = makeViewModel(.near, ticker: "NEAR", decimals: 24, address: "al")

        vm.handleAddressResolution(true)

        XCTAssertTrue(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testAResolvedAddressOnAChainWithoutPrefixValidAddressesMovesOnToAmount() {
        let vm = makeViewModel(.ethereum, ticker: "ETH", decimals: 18, address: "0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF")

        vm.handleAddressResolution(true)

        XCTAssertEqual(vm.selectedTab, .amount)
    }

    private func makeViewModel(_ chain: Chain, ticker: String, decimals: Int, address: String) -> SendDetailsViewModel {
        let coin = SendFormFixture.makeCoin(chain, ticker: ticker, decimals: decimals, isNative: true)
        let vm = SendFormFixture.make(coin: coin)
        vm.onSelect(tab: .address)
        vm.toAddress = address
        return vm
    }
}
