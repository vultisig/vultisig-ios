//
//  RippleDestinationTagViewModelTests.swift
//  VultisigAppTests
//
//  Pins the pure seams extracted out of `SendDetailsViewModel` into the
//  XRP-only `RippleDestinationTagViewModel`: the X-address autofill/lock
//  lifecycle, the tag/memo validation outcome, the resolved tag, and the
//  RequireDest gate outcome (nudge / alert / cache / ack). The end-to-end
//  send-form behavior stays pinned by the parent-level integration tests
//  (RippleXAddressAutofillTests / RippleDestinationTagThreadingTests /
//  RippleRequireDestGateTests) asserting through `parent.rippleTag`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class RippleDestinationTagViewModelTests: XCTestCase {

    private let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private let otherDestination = "r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59"

    // MARK: - X-address autofill / lock lifecycle

    func testApplyDecodedTagWithTagAutofillsAndLocks() {
        let vm = RippleDestinationTagViewModel()
        vm.applyDecodedTag(1)
        XCTAssertEqual(vm.destinationTag, "1")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testApplyDecodedTagNilReleasesPriorLock() {
        let vm = RippleDestinationTagViewModel()
        vm.applyDecodedTag(1)
        vm.applyDecodedTag(nil)
        XCTAssertEqual(vm.destinationTag, "")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    func testApplyDecodedTagNilLeavesManualTagUntouched() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "777"
        vm.applyDecodedTag(nil)
        XCTAssertEqual(vm.destinationTag, "777", "unlocked user-typed tag is preserved")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    func testApplyDecodedTagZeroLocksButKeepsRawValue() {
        // XLS-5d tag 0 autofills and locks; the tag-validation rule rejects it
        // later — this method only performs the autofill.
        let vm = RippleDestinationTagViewModel()
        vm.applyDecodedTag(0)
        XCTAssertEqual(vm.destinationTag, "0")
        XCTAssertTrue(vm.isDestinationTagLocked)
    }

    func testHandleAddressChangedAwayReleasesLockWhenNotStillResolved() {
        let vm = RippleDestinationTagViewModel()
        vm.applyDecodedTag(1)
        vm.handleAddressChangedAway(isStillResolved: false)
        XCTAssertFalse(vm.isDestinationTagLocked)
        XCTAssertEqual(vm.destinationTag, "")
    }

    func testHandleAddressChangedAwayKeepsLockWhenStillResolved() {
        let vm = RippleDestinationTagViewModel()
        vm.applyDecodedTag(1)
        vm.handleAddressChangedAway(isStillResolved: true)
        XCTAssertTrue(vm.isDestinationTagLocked, "re-validating the normalized address keeps the lock")
        XCTAssertEqual(vm.destinationTag, "1")
    }

    func testReleaseLockedTagIsNoOpWhenUnlocked() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "42"
        vm.releaseLockedTag()
        XCTAssertEqual(vm.destinationTag, "42", "an unlocked tag is untouched")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    func testClearForUnsupportedChainDropsTagUnconditionally() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "42"
        vm.clearForUnsupportedChain()
        XCTAssertEqual(vm.destinationTag, "")
        XCTAssertFalse(vm.isDestinationTagLocked)
    }

    // MARK: - Tag / memo validation outcome

    func testValidateTagAndMemoValid() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "12345"
        XCTAssertEqual(vm.validateTagAndMemo(memo: ""), .valid)
    }

    func testValidateTagAndMemoInvalidTag() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "0123"
        let outcome = vm.validateTagAndMemo(memo: "")
        XCTAssertEqual(outcome, .invalidTag)
        XCTAssertEqual(outcome.errorKey, "destinationTagInvalidError")
    }

    func testValidateTagAndMemoZeroTagRejected() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "0"
        XCTAssertEqual(vm.validateTagAndMemo(memo: ""), .invalidTag)
    }

    func testValidateTagAndMemoTextMemoAcceptedAsMemoOnly() {
        // #4755: a text memo (no tag) is valid again — it rides on-chain as a
        // Memos blob (memo-only send).
        let vm = RippleDestinationTagViewModel()
        XCTAssertEqual(vm.validateTagAndMemo(memo: "thanks for lunch"), .valid)
    }

    func testValidateTagAndMemoTagPlusTextMemoIsCombo() {
        // #4755: a tag field alongside a genuine text memo is the valid combo.
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "12345"
        XCTAssertEqual(vm.validateTagAndMemo(memo: "gift for alice"), .valid)
    }

    func testValidateTagAndMemoZeroMemoRejected() {
        // A numeric-canonical "0" memo (no tag) is the legacy tag carrier and a
        // zero tag can't sign — still rejected.
        let vm = RippleDestinationTagViewModel()
        XCTAssertEqual(vm.validateTagAndMemo(memo: "0"), .invalidTag)
    }

    func testValidateTagAndMemoConflict() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "42"
        let outcome = vm.validateTagAndMemo(memo: "43")
        XCTAssertEqual(outcome, .tagMemoConflict)
        XCTAssertEqual(outcome.errorKey, "destinationTagMemoConflictError")
    }

    func testValidateTagAndMemoMatchingTagAndMemoValid() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "42"
        XCTAssertEqual(vm.validateTagAndMemo(memo: "42"), .valid)
    }

    // MARK: - Resolved tag

    func testResolvedTagPrefersField() {
        let vm = RippleDestinationTagViewModel()
        vm.destinationTag = "12345"
        XCTAssertEqual(vm.resolvedTag(memo: "999"), 12345)
    }

    func testResolvedTagFallsBackToNumericMemo() {
        let vm = RippleDestinationTagViewModel()
        XCTAssertEqual(vm.resolvedTag(memo: "777"), 777)
    }

    func testResolvedTagNilWhenNeitherSet() {
        let vm = RippleDestinationTagViewModel()
        XCTAssertNil(vm.resolvedTag(memo: ""))
    }

    // MARK: - RequireDest gate outcome

    private final class ProviderSpy {
        var calls: [String] = []
        var result: RippleDestinationTagRequirement
        init(result: RippleDestinationTagRequirement) { self.result = result }
    }

    private func makeVM(spy: ProviderSpy) -> RippleDestinationTagViewModel {
        RippleDestinationTagViewModel(requirementProvider: { address in
            spy.calls.append(address)
            return spy.result
        })
    }

    func testRequireDestSatisfiedWhenTagPresent() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeVM(spy: spy)
        vm.destinationTag = "12345"
        let outcome = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(outcome, .satisfied)
        XCTAssertTrue(spy.calls.isEmpty, "a present tag short-circuits the lookup")
    }

    func testRequireDestRequiredBumpsNudge() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeVM(spy: spy)
        let outcome = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(outcome, .required)
        XCTAssertEqual(vm.destinationTagFieldNudge, 1)
    }

    func testRequireDestNotRequiredSatisfied() async {
        let spy = ProviderSpy(result: .notRequired)
        let vm = makeVM(spy: spy)
        let outcome = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(outcome, .satisfied)
    }

    func testRequireDestUnknownSetsAlertThenPassesAfterAck() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeVM(spy: spy)

        let first = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(first, .unverified)
        XCTAssertTrue(vm.showDestinationTagUnverifiedAlert)

        vm.acknowledge(toAddress: destination)
        let second = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(second, .satisfied)
    }

    func testRequireDestAckDoesNotCarryToDifferentAddress() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeVM(spy: spy)
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        vm.acknowledge(toAddress: destination)

        let outcome = await vm.validateRequireDest(toAddress: otherDestination, memo: "")
        XCTAssertEqual(outcome, .unverified, "the acknowledgment was for the previous address")
    }

    func testRequireDestCachesDefinitiveResultPerAddress() async {
        let spy = ProviderSpy(result: .notRequired)
        let vm = makeVM(spy: spy)
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(spy.calls.count, 1)
    }

    func testRequireDestDoesNotCacheUnknown() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeVM(spy: spy)
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(spy.calls.count, 2, "a failed lookup retries next time")
    }

    // MARK: - Reset

    func testResetClearsTagStateButNotNudge() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeVM(spy: spy)
        // Trigger the RequireDest nudge on a tagless send first, then lock a
        // tag so reset has both to clear.
        _ = await vm.validateRequireDest(toAddress: destination, memo: "")
        XCTAssertEqual(vm.destinationTagFieldNudge, 1)
        vm.applyDecodedTag(5)

        vm.reset()
        XCTAssertEqual(vm.destinationTag, "")
        XCTAssertFalse(vm.isDestinationTagLocked)
        XCTAssertFalse(vm.showDestinationTagUnverifiedAlert)
        XCTAssertEqual(vm.destinationTagFieldNudge, 1, "reset intentionally leaves the nudge intact")
    }
}
