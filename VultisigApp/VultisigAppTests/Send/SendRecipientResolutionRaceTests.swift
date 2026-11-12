//
//  SendRecipientResolutionRaceTests.swift
//  VultisigAppTests
//
//  A recipient lookup that returns after the recipient or the chain changed
//  must not rewrite the newer recipient, mark it invalid, or move the step.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SendRecipientResolutionRaceTests: XCTestCase {

    private static let name = "alice.eth"
    private static let nameOwner = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    private static let newerRecipient = "0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF"

    private var token: TestContextToken?
    private var release: AsyncStream<Void>.Continuation?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        release?.finish()
        release = nil
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testALookupThatReturnsAfterTheRecipientChangedCommitsNothing() async {
        let (vm, lookupStarted) = makeViewModelResolvingTheName()
        let lookup = Task { await vm.validateToAddressIfUnchanged() }
        await fulfillment(of: [lookupStarted], timeout: 3)

        vm.toAddress = Self.newerRecipient
        vm.handleToAddressChange()
        let stepAfterEdit = vm.selectedTab
        release?.yield()
        let result = await lookup.value

        XCTAssertNil(result)
        XCTAssertEqual(vm.toAddress, Self.newerRecipient)
        XCTAssertNil(vm.toAddressLabel)
        XCTAssertFalse(vm.showAddressAlert)
        XCTAssertTrue(vm.addressSetupDone)
        XCTAssertEqual(vm.selectedTab, stepAfterEdit)
    }

    func testALookupThatReturnsAfterTheChainChangedCommitsNothing() async {
        let (vm, lookupStarted) = makeViewModelResolvingTheName()
        let lookup = Task { await vm.validateToAddressIfUnchanged() }
        await fulfillment(of: [lookupStarted], timeout: 3)

        vm.coin = SendFormFixture.makeCoin(.polygon, ticker: "POL", decimals: 18, isNative: true)
        release?.yield()
        let result = await lookup.value

        XCTAssertNil(result)
        XCTAssertEqual(vm.toAddress, Self.name)
        XCTAssertNil(vm.toAddressLabel)
        XCTAssertFalse(vm.isNamespaceResolved)
        XCTAssertFalse(vm.showAddressAlert)
        XCTAssertEqual(vm.selectedTab, .address)
    }

    func testContinueFailsClosedWhenItsLookupWasSuperseded() async {
        let (vm, lookupStarted) = makeViewModelResolvingTheName()
        let lookup = Task { await vm.validateToAddress() }
        await fulfillment(of: [lookupStarted], timeout: 3)

        vm.toAddress = Self.newerRecipient
        release?.yield()
        let isValid = await lookup.value

        XCTAssertFalse(isValid)
        XCTAssertEqual(vm.toAddress, Self.newerRecipient)
        XCTAssertNil(vm.toAddressLabel)
    }

    /// An Ethereum form on the Address step whose name lookup waits for `release`.
    private func makeViewModelResolvingTheName() -> (SendDetailsViewModel, XCTestExpectation) {
        let lookupStarted = expectation(description: "lookup started")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        release = continuation
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), addressResolver: { _, _ in
            lookupStarted.fulfill()
            for await _ in gate { break }
            return Self.nameOwner
        })
        vm.onSelect(tab: .address)
        vm.toAddress = Self.name
        return (vm, lookupStarted)
    }
}
