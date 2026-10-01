import XCTest
@testable import VultisigApp

final class WalletConnectEVMChainResolverTests: XCTestCase {
    private let resolver = WalletConnectEVMChainResolver()

    func testResolvesCAIP2EVMChainByChainID() throws {
        XCTAssertEqual(try resolver.resolve("eip155:1"), .ethereum)
        XCTAssertEqual(try resolver.resolve("eip155:8453"), .base)
    }

    func testRejectsMissingChain() {
        XCTAssertThrowsError(try resolver.resolve(nil)) { error in
            XCTAssertEqual(error as? WalletConnectMessageRequestError, .missingChainId)
        }
    }

    func testRejectsUnsupportedNamespaceOrChain() {
        XCTAssertThrowsError(try resolver.resolve("solana:mainnet")) { error in
            XCTAssertEqual(error as? WalletConnectMessageRequestError, .unsupportedChain("solana:mainnet"))
        }
        XCTAssertThrowsError(try resolver.resolve("eip155:999999999")) { error in
            XCTAssertEqual(error as? WalletConnectMessageRequestError, .unsupportedChain("eip155:999999999"))
        }
    }
}
