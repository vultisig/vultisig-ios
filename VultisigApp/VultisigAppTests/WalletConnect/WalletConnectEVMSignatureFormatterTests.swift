import XCTest
@testable import VultisigApp

final class WalletConnectEVMSignatureFormatterTests: XCTestCase {
    private let formatter = WalletConnectEVMSignatureFormatter()

    func testNormalizesRecoveryIDZeroAndAddsHexPrefix() throws {
        let signature = String(repeating: "ab", count: 64) + "00"

        let normalized = try formatter.normalizedSignature(signature)

        XCTAssertEqual(normalized, "0x" + String(repeating: "ab", count: 64) + "1b")
    }

    func testNormalizesRecoveryIDOne() throws {
        let signature = "0x" + String(repeating: "cd", count: 64) + "01"

        let normalized = try formatter.normalizedSignature(signature)

        XCTAssertEqual(normalized, "0x" + String(repeating: "cd", count: 64) + "1c")
    }

    func testRejectsNon65ByteSignature() {
        XCTAssertThrowsError(try formatter.normalizedSignature("0x1234")) { error in
            XCTAssertEqual(
                error as? WalletConnectMessageRequestError,
                .invalidSignature("expected 65-byte ECDSA signature")
            )
        }
    }
}
