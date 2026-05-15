//
//  SendRetrySignalTests.swift
//  VultisigAppTests
//
//  Locks down the single-shot retry signal that threads `Keysign → Verify`.
//  The class is tiny (`@Observable final class` with one field) but its
//  semantics matter: identity-based equality, observable mutation, and
//  the consumer pattern of "read once + clear".
//

import XCTest
@testable import VultisigApp

@MainActor
final class SendRetrySignalTests: XCTestCase {

    func testInitDefaultsPendingReasonToNil() {
        let signal = SendRetrySignal()
        XCTAssertNil(signal.pendingRetryReason)
    }

    func testEqualityIsReferenceIdentity() {
        let a = SendRetrySignal()
        let b = SendRetrySignal()
        XCTAssertEqual(a, a, "Same instance must equal itself")
        XCTAssertNotEqual(a, b, "Different instances must not equal each other even with same field values")
    }

    func testHashUsesObjectIdentifier() {
        let a = SendRetrySignal()
        var hasherA = Hasher()
        a.hash(into: &hasherA)

        var hasherAgain = Hasher()
        a.hash(into: &hasherAgain)

        XCTAssertEqual(hasherA.finalize(), hasherAgain.finalize(),
                       "Same instance must hash to the same value across calls")
    }

    func testPendingReasonRoundTripsAcrossSetAndClear() {
        let signal = SendRetrySignal()
        signal.pendingRetryReason = .other("test reason")
        XCTAssertNotNil(signal.pendingRetryReason)

        signal.pendingRetryReason = nil
        XCTAssertNil(signal.pendingRetryReason,
                     "Consumer clears after reading — the next observer must see nil")
    }

    func testHashableConformanceLetsSignalLiveInSetAndDict() {
        // Used as a route param — must be Hashable for SwiftUI NavigationStack
        // value-equality. Pin that the conformance compiles + behaves as
        // identity-based.
        let a = SendRetrySignal()
        let b = SendRetrySignal()
        let set: Set<SendRetrySignal> = [a, b]
        XCTAssertEqual(set.count, 2, "Two distinct instances are two distinct set members")
    }
}
