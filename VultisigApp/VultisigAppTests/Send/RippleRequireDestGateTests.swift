//
//  RippleRequireDestGateTests.swift
//  VultisigAppTests
//
//  Pins the Send-form RequireDest gate: a tagless XRP send to a destination
//  whose AccountRoot sets lsfRequireDestTag is hard-blocked; a failed lookup
//  fails OPEN behind an explicit per-address user acknowledgment; results
//  are cached per address so repeated Continue presses don't re-query.
//

import XCTest
@testable import VultisigApp

@MainActor
final class RippleRequireDestGateTests: XCTestCase {

    private let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private let otherDestination = "r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59"

    private final class ProviderSpy {
        var calls: [String] = []
        var result: RippleDestinationTagRequirement

        init(result: RippleDestinationTagRequirement) {
            self.result = result
        }
    }

    private func makeForm(spy: ProviderSpy) -> SendDetailsViewModel {
        let xrp = SendFormFixture.makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: "100000000")
        let vm = SendFormFixture.make(
            coin: xrp,
            destinationTagRequirementProvider: { address in
                spy.calls.append(address)
                return spy.result
            }
        )
        vm.toAddress = destination
        vm.amount = "1.0"
        return vm
    }

    func testRequireDestBlocksTaglessSend() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeForm(spy: spy)

        let passed = await vm.validateRippleRequireDest()
        XCTAssertFalse(passed)
        XCTAssertEqual(vm.errorMessage, "destinationTagRequiredError")
        XCTAssertEqual(spy.calls, [destination])
    }

    func testRequireDestSkippedWhenTagPresent() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeForm(spy: spy)
        vm.rippleTag.destinationTag = "12345"

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed, "a present tag satisfies any RequireDest flag")
        XCTAssertTrue(spy.calls.isEmpty, "no lookup needed when the tag is set")
    }

    func testRequireDestSkippedWhenNumericMemoCarriesTag() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeForm(spy: spy)
        vm.memo = "12345"

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed, "the legacy tag-in-memo workaround counts as a tag")
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testNotRequiredPasses() async {
        let spy = ProviderSpy(result: .notRequired)
        let vm = makeForm(spy: spy)

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed)
    }

    func testAccountNotFoundPasses() async {
        // Unfunded destination — cannot have the flag; the reserve/funding
        // problem is a different check's job.
        let spy = ProviderSpy(result: .accountNotFound)
        let vm = makeForm(spy: spy)

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed)
    }

    func testUnknownBlocksAndAsksForAcknowledgment() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeForm(spy: spy)

        let passed = await vm.validateRippleRequireDest()
        XCTAssertFalse(passed, "first pass blocks pending explicit acknowledgment")
        XCTAssertTrue(vm.rippleTag.showDestinationTagUnverifiedAlert)
    }

    func testUnknownPassesAfterAcknowledgment() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeForm(spy: spy)

        _ = await vm.validateRippleRequireDest()
        vm.acknowledgeUnverifiedDestinationTag()

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed, "fail-open once the user explicitly accepted the risk")
    }

    func testAcknowledgmentDoesNotCarryToDifferentAddress() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeForm(spy: spy)

        _ = await vm.validateRippleRequireDest()
        vm.acknowledgeUnverifiedDestinationTag()

        vm.toAddress = otherDestination
        let passed = await vm.validateRippleRequireDest()
        XCTAssertFalse(passed, "the acknowledgment was for the previous address")
    }

    func testRequirementCachedPerAddress() async {
        let spy = ProviderSpy(result: .notRequired)
        let vm = makeForm(spy: spy)

        _ = await vm.validateRippleRequireDest()
        _ = await vm.validateRippleRequireDest()
        XCTAssertEqual(spy.calls.count, 1, "definitive results are cached per address")
    }

    func testUnknownResultIsNotCached() async {
        let spy = ProviderSpy(result: .unknown)
        let vm = makeForm(spy: spy)

        _ = await vm.validateRippleRequireDest()
        _ = await vm.validateRippleRequireDest()
        XCTAssertEqual(spy.calls.count, 2, "a failed lookup retries on the next attempt")
    }

    func testRequiredResultRechecksAfterTagEntered() async {
        let spy = ProviderSpy(result: .required)
        let vm = makeForm(spy: spy)

        let blocked = await vm.validateRippleRequireDest()
        XCTAssertFalse(blocked)

        vm.rippleTag.destinationTag = "12345"
        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed)
    }

    func testNonRippleChainSkipsRule() async {
        let spy = ProviderSpy(result: .required)
        let btc = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(
            coin: btc,
            destinationTagRequirementProvider: { address in
                spy.calls.append(address)
                return spy.result
            }
        )
        vm.toAddress = "bc1qexample"

        let passed = await vm.validateRippleRequireDest()
        XCTAssertTrue(passed)
        XCTAssertTrue(spy.calls.isEmpty)
    }
}
