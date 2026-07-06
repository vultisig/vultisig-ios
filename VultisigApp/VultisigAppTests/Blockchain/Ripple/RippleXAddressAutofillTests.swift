//
//  RippleXAddressAutofillTests.swift
//  VultisigAppTests
//
//  Pins the Send-form X-address seam: pasting (or scanning / picking from
//  the address book — everything lands in `toAddress`) a mainnet X-address
//  normalizes the field to the embedded classic r-address, keeps the
//  original X string visible as the address label, and autofills + locks
//  the Destination Tag when one is embedded.
//

import XCTest
@testable import VultisigApp

@MainActor
final class RippleXAddressAutofillTests: XCTestCase {

    // Canonical xrpl.js vectors (see RippleXAddressTests).
    private let taggedXAddress = "X7AcgcsBL6XDcUb289X4mJ8djcdyKaGZMhc9YTE92ehJ2Fu"   // r9cZA1... tag 1
    private let untaggedXAddress = "X7AcgcsBL6XDcUb289X4mJ8djcdyKaB5hJDWMArnXr61cqZ" // r9cZA1... no tag
    private let classicAddress = "r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59"
    private let otherClassicAddress = "rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf"
    private let zeroTagXAddress = "XVLhHMPHU98es4dbozjVtdWzVrDjtV8AqEL4xcZj5whKbmc"  // rGWr... tag 0

    private func makeRippleForm() -> SendDetailsViewModel {
        let xrp = SendFormFixture.makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: xrp)
        vm.amount = "1.0"
        return vm
    }

    func testXAddressPasteNormalizesToClassicAndLocksTag() {
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress

        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.toAddress, classicAddress, "payload must carry the classic address, never the X form")
        XCTAssertEqual(vm.toAddressLabel, taggedXAddress, "original X-address stays visible as the label")
        XCTAssertEqual(vm.destinationTag, "1")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testXAddressWithoutTagLeavesTagEditable() {
        let vm = makeRippleForm()
        vm.destinationTag = "777"
        vm.toAddress = untaggedXAddress

        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.toAddress, classicAddress)
        XCTAssertEqual(vm.toAddressLabel, untaggedXAddress)
        XCTAssertEqual(vm.destinationTag, "777", "no embedded tag — the user's tag stays")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    func testXAddressOverridesPreviouslyTypedTag() {
        let vm = makeRippleForm()
        vm.destinationTag = "999"
        vm.toAddress = taggedXAddress

        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.destinationTag, "1", "the embedded tag wins and locks")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testManualAddressEditAfterXAddressUnlocksAndClearsTag() {
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertTrue(vm.isDestinationTagLocked)

        // User replaces the address with an unrelated classic one — the
        // derived tag belonged to the old destination and must not ride along.
        vm.toAddress = otherClassicAddress
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.toAddress, otherClassicAddress)
        XCTAssertFalse(vm.isDestinationTagLocked)
        XCTAssertEqual(vm.destinationTag, "")
    }

    func testRevalidatingNormalizedAddressKeepsLock() {
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress
        XCTAssertTrue(vm.isValidAddressFormat())

        // The screen re-runs format validation on the (now classic) address;
        // the lock and tag must survive.
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.destinationTag, "1")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testZeroTagXAddressAutofillsButFailsTagValidation() {
        // XLS-5d allows an embedded tag 0, but no wallet-core-based signer
        // can express present-with-0 — the form surfaces it and validation
        // blocks loudly instead of signing an untagged payment.
        let vm = makeRippleForm()
        vm.toAddress = zeroTagXAddress

        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertEqual(vm.destinationTag, "0")
        XCTAssertTrue(vm.isDestinationTagLocked)
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    func testValidateToAddressNormalizesXAddressToo() async {
        // The async ENS-style resolution path must hit the same seam
        // (deeplinks and prefills go through it).
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress

        let resolved = await vm.validateToAddress()
        XCTAssertTrue(resolved)
        XCTAssertEqual(vm.toAddress, classicAddress)
        XCTAssertEqual(vm.destinationTag, "1")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testNonRippleChainIgnoresXAddressSeam() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.toAddress = taggedXAddress

        XCTAssertFalse(vm.isValidAddressFormat(), "an X-address is not a BTC address")
        XCTAssertEqual(vm.toAddress, taggedXAddress, "no normalization outside Ripple")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    func testClearingAddressReleasesLockAndDropsDerivedTag() {
        // Clearing the field bypasses the normalization seam (empty input
        // early-returns), so the screen's clear hook must release the lock —
        // otherwise re-entering the same classic address would revive the
        // old X-address's tag, locked and uneditable.
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertTrue(vm.isDestinationTagLocked)

        vm.toAddress = ""
        vm.onToAddressCleared()
        XCTAssertFalse(vm.isDestinationTagLocked)
        XCTAssertEqual(vm.destinationTag, "")
        XCTAssertNil(vm.toAddressLabel)

        vm.toAddress = classicAddress
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertFalse(vm.isDestinationTagLocked, "bare classic re-entry must not revive the old tag")
        XCTAssertEqual(vm.destinationTag, "")
    }

    func testValidateFormRejectsZeroTagXAddressOnPrefillPath() async {
        // Prefill paths can reach validateForm() with a raw X-address that
        // never went through the screen's format check. Address resolution
        // (and its normalization seam) must run before the tag rule so an
        // embedded tag 0 is autofilled and then REJECTED — not silently
        // dropped into a tagless payment behind a displayed tag.
        let xrp = SendFormFixture.makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: "100000000")
        let vm = SendFormFixture.make(
            coin: xrp,
            destinationTagRequirementProvider: { _ in .notRequired }
        )
        vm.amount = "1.0"
        vm.toAddress = zeroTagXAddress

        let passed = await vm.validateForm()
        XCTAssertFalse(passed)
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
        XCTAssertEqual(vm.destinationTag, "0", "the embedded tag surfaced before rejection")
    }

    func testResetClearsLock() {
        let vm = makeRippleForm()
        vm.toAddress = taggedXAddress
        XCTAssertTrue(vm.isValidAddressFormat())
        XCTAssertTrue(vm.isDestinationTagLocked)

        vm.reset(to: SendFormFixture.makeBTC())
        XCTAssertFalse(vm.isDestinationTagLocked)
        XCTAssertEqual(vm.destinationTag, "")
    }
}
