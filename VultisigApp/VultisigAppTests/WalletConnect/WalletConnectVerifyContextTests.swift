import XCTest
@testable import VultisigApp

final class WalletConnectVerifyContextTests: XCTestCase {
    func testValidContextUsesVerifiedButDisplayOnlyCopy() {
        let context = WalletConnectVerifyContext(origin: "https://example.com", validation: .valid)

        XCTAssertEqual(context.titleLocalizationKey, "walletConnectVerifyValidTitle")
        XCTAssertEqual(context.messageLocalizationKey, "walletConnectVerifyValidMessage")
        XCTAssertFalse(context.isWarning)
    }

    func testRiskContextsAreWarnings() {
        XCTAssertTrue(WalletConnectVerifyContext(origin: "https://example.com", validation: .unknown).isWarning)
        XCTAssertTrue(WalletConnectVerifyContext(origin: "https://example.com", validation: .invalid).isWarning)
        XCTAssertTrue(WalletConnectVerifyContext(origin: "https://example.com", validation: .scam).isWarning)
    }
}
