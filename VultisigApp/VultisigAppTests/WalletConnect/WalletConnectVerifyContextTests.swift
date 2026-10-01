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

    func testProposalCarriesTypedVerifyContextForDisplayOnlyRiskCopy() {
        let verifyContext = WalletConnectVerifyContext(origin: "https://dapp.example", validation: .scam)
        let proposal = WalletConnectProposal(
            id: "proposal-1",
            name: "Risky dapp",
            url: "https://dapp.example/wc",
            icons: [],
            verifyContext: verifyContext,
            requiredNamespaces: [],
            optionalNamespaces: [],
            sessionProperties: nil
        )

        XCTAssertEqual(proposal.verifyContext, verifyContext)
        XCTAssertEqual(proposal.verifyContext?.titleLocalizationKey, "walletConnectVerifyScamTitle")
        XCTAssertEqual(proposal.verifyContext?.messageLocalizationKey, "walletConnectVerifyScamMessage")
        XCTAssertEqual(proposal.displayHost, "dapp.example")
    }
}
