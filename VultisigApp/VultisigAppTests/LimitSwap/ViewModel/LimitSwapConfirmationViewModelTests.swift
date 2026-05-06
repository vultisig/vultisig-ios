//
//  LimitSwapConfirmationViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class LimitSwapConfirmationViewModelTests: XCTestCase {

    // MARK: - canSign

    func testCanSignFalseInitially() {
        let vm = makeVM(memo: validMemo)
        XCTAssertFalse(vm.canSign)
    }

    func testCanSignFalseUntilCheckboxToggled() {
        let vm = makeVM(memo: validMemo)
        XCTAssertFalse(vm.canSign)
        vm.toggleAmountCorrect()
        XCTAssertTrue(vm.canSign)
    }

    func testCanSignFalseAfterCheckboxUnchecked() {
        let vm = makeVM(memo: validMemo)
        vm.toggleAmountCorrect()
        vm.toggleAmountCorrect()
        XCTAssertFalse(vm.canSign)
    }

    func testCanSignFalseWhenByteCapErrorPresent() {
        let vm = makeVM(memo: validMemo)
        vm.toggleAmountCorrect()
        vm.byteCapError = .memoExceedsByteLimit(actual: 100, limit: 80)
        XCTAssertFalse(vm.canSign)
    }

    // MARK: - attemptSign

    func testAttemptSignInvokesPerformWhenChecksPass() async {
        let vm = makeVM(memo: validMemo)
        vm.toggleAmountCorrect()

        var performCalled = false
        await vm.attemptSign { performCalled = true }

        XCTAssertTrue(performCalled)
        XCTAssertNil(vm.byteCapError)
    }

    func testAttemptSignSkipsPerformWhenByteCapFails() async {
        let oversizedMemo = String(repeating: "x", count: 81) // > 80B for UTXO
        let vm = makeVM(memo: oversizedMemo, sourceChainKind: .UTXO)
        vm.toggleAmountCorrect()

        var performCalled = false
        await vm.attemptSign { performCalled = true }

        XCTAssertFalse(performCalled, "performSign must not run when the pre-flight fails")
        guard case let .memoExceedsByteLimit(actual, limit) = vm.byteCapError else {
            return XCTFail("Expected byteCapError to be memoExceedsByteLimit, got \(String(describing: vm.byteCapError))")
        }
        XCTAssertEqual(actual, 81)
        XCTAssertEqual(limit, 80)
    }

    func testAttemptSignClearsPreviousByteCapErrorOnSuccess() async {
        let vm = makeVM(memo: validMemo)
        vm.toggleAmountCorrect()
        vm.byteCapError = .memoExceedsByteLimit(actual: 99, limit: 80)

        await vm.attemptSign { /* no-op */ }

        XCTAssertNil(vm.byteCapError)
    }

    func testAttemptSignSwallowsErrorsThrownByPerformSign() async {
        // The VM only owns byte-cap pre-flight failure. Other errors from the
        // real sign machinery surface through that machinery's own error UI.
        struct UpstreamSignError: Error {}
        let vm = makeVM(memo: validMemo)
        vm.toggleAmountCorrect()

        await vm.attemptSign { throw UpstreamSignError() }

        XCTAssertNil(vm.byteCapError, "Non-byte-cap errors must not pollute byteCapError")
    }

    // MARK: - Fixtures

    private let validMemo = "=<:ETH.ETH:0xabc:1600000000/14400/0:vi:50"

    private func makeVM(
        memo: String,
        sourceChainKind: ChainType = .EVM
    ) -> LimitSwapConfirmationViewModel {
        let draft = LimitSwapDraft(
            fromAsset: LimitSwapAsset(chain: .ethereum, ticker: "ETH", decimals: 18, contractAddress: "ETH-c", isNativeToken: true),
            toAsset: LimitSwapAsset(chain: .bitcoin, ticker: "BTC", decimals: 8, contractAddress: "BTC-c", isNativeToken: true),
            sourceAmount: BigInt("1000000000000000000"),
            targetPrice: Decimal(string: "0.0625")!,
            expiryHours: 24
        )
        return LimitSwapConfirmationViewModel(
            draft: draft,
            memo: memo,
            sourceChainKind: sourceChainKind
        )
    }
}

