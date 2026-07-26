//
//  SendAmountValidatorTests.swift
//  VultisigAppTests
//
//  Covers the chain-agnostic `SendAmountValidator` wiring on the send form VM,
//  independent of any specific chain: an injected validator that objects sets
//  the inline message, disables Continue, and blocks `validateForm()`; the
//  Continue-time gate always runs live (`forceRefresh`); and the first
//  applicable validator to object wins.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SendAmountValidatorTests: XCTestCase {

    func testBlockingValidatorSetsMessageAndDisablesContinue() async {
        let validator = RecordingValidator(applicable: true, result: .invalid(message: "over the limit", blocksContinue: true))
        let vm = makeVM(validators: [validator])

        await vm.refreshAmountValidation()

        XCTAssertEqual(vm.amountValidation.message, "over the limit")
        XCTAssertTrue(vm.amountValidation.blocksContinue)
        XCTAssertTrue(vm.continueButtonDisabled, "a blocking validator message disables Continue")
    }

    func testNonBlockingValidatorShowsMessageButAllowsContinue() async {
        let validator = RecordingValidator(applicable: true, result: .invalid(message: "heads up", blocksContinue: false))
        let vm = makeVM(validators: [validator])

        await vm.refreshAmountValidation()

        XCTAssertEqual(vm.amountValidation.message, "heads up")
        XCTAssertFalse(vm.continueButtonDisabled, "a non-blocking message is advisory only")
    }

    func testInapplicableValidatorClearsMessageAndDoesNotRun() async {
        let validator = RecordingValidator(applicable: false, result: .invalid(message: "unused", blocksContinue: true))
        let vm = makeVM(validators: [validator])
        vm.amountValidation = SendAmountValidationState(message: "stale", blocksContinue: true)

        await vm.refreshAmountValidation()

        XCTAssertEqual(vm.amountValidation, .valid)
        XCTAssertTrue(validator.forceRefreshCalls.isEmpty, "an inapplicable validator is never consulted")
    }

    func testContinueGateForcesLiveRefreshAndBlocks() async {
        let validator = RecordingValidator(applicable: true, result: .invalid(message: "nope", blocksContinue: true))
        let vm = makeVM(validators: [validator])

        let allowed = await vm.validateAmountConstraints()

        XCTAssertFalse(allowed, "the Continue-time gate blocks on a blocking verdict")
        XCTAssertEqual(validator.forceRefreshCalls, [true], "the Continue-time gate always runs live")
    }

    func testFirstApplicableObjectionWins() async {
        let first = RecordingValidator(applicable: true, result: .invalid(message: "first", blocksContinue: true))
        let second = RecordingValidator(applicable: true, result: .invalid(message: "second", blocksContinue: true))
        let vm = makeVM(validators: [first, second])

        await vm.refreshAmountValidation()

        XCTAssertEqual(vm.amountValidation.message, "first")
        XCTAssertTrue(second.forceRefreshCalls.isEmpty, "a preceding objection short-circuits later validators")
    }

    // MARK: - Fixtures

    private func makeVM(validators: [any SendAmountValidator]) -> SendDetailsViewModel {
        let vm = SendFormFixture.make(
            coin: SendFormFixture.makeETH(),
            addressResolver: { input, _ in input },
            amountValidators: validators
        )
        vm.toAddress = "0x000000000000000000000000000000000000dEaD"
        vm.amount = "1"
        return vm
    }
}

// swiftlint:disable async_without_await

/// A chain-agnostic test double: records the `forceRefresh` value of each
/// `validate` call so the VM's while-typing vs Continue-time paths can be told
/// apart, and returns a canned verdict. `validate` is `async` to satisfy the
/// protocol; this stub answers synchronously.
private final class RecordingValidator: SendAmountValidator, @unchecked Sendable {
    private let applicable: Bool
    private let result: SendAmountValidatorResult
    private(set) var forceRefreshCalls: [Bool] = []

    init(applicable: Bool, result: SendAmountValidatorResult) {
        self.applicable = applicable
        self.result = result
    }

    func isApplicable(to _: SendAmountValidationInput) -> Bool { applicable }

    func validate(_: SendAmountValidationInput, forceRefresh: Bool) async -> SendAmountValidatorResult {
        forceRefreshCalls.append(forceRefresh)
        return result
    }
}
// swiftlint:enable async_without_await
