//
//  KeychainReadResultAssertions.swift
//  VultisigAppTests
//
//  Asserting on a `KeychainReadResult` directly, rather than collapsing it to an
//  optional first. Two reasons: it is only `Equatable` when its value is, and
//  `SymmetricKey` is not; and "absent" has to be asserted rather than
//  approximated by "not present", because the third answer is neither and the
//  whole point of the type is that the difference decides whether key material
//  may be overwritten.
//

import Security
import XCTest
@testable import VultisigApp

func XCTAssertAbsent<Value>(
    _ result: KeychainReadResult<Value>,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .absent = result else {
        XCTFail(describeFailure(expected: "absent", got: result, message()), file: file, line: line)
        return
    }
}

func XCTAssertUnavailable<Value>(
    _ result: KeychainReadResult<Value>,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .unavailable = result else {
        XCTFail(describeFailure(expected: "unavailable", got: result, message()), file: file, line: line)
        return
    }
}

/// The stored value, failing the test if the Keychain answered anything else.
func XCTUnwrapPresent<Value>(
    _ result: KeychainReadResult<Value>,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Value {
    guard case .present(let value) = result else {
        XCTFail(describeFailure(expected: "present", got: result, message()), file: file, line: line)
        throw XCTSkip("not present")
    }
    return value
}

private func describeFailure<Value>(
    expected: String,
    got result: KeychainReadResult<Value>,
    _ message: String
) -> String {
    let actual: String
    switch result {
    case .absent:
        actual = "absent"
    case .present:
        actual = "present"
    case .unavailable(let status):
        actual = "unavailable(\(status))"
    }
    let detail = "expected \(expected), got \(actual)"
    return message.isEmpty ? detail : "\(message) — \(detail)"
}
