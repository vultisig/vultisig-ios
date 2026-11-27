//
//  PerpsTradingAccountTests.swift
//  VultisigAppTests
//
//  The trading-account address against an independent oracle:
//  @scure/bip32 non-hardened derivation from (root pubkey, chain code) with
//  apostrophes stripped, as vultisig-sdk's derivePublicKey does
//  (VultisigAppTests/Perps/Vectors/gen_trading_address.mjs). The root pubkey is
//  the Python SDK's public test key; the chain code is arbitrary.
//

import WalletCore
import XCTest
@testable import VultisigApp

final class PerpsTradingAccountTests: XCTestCase {
    private static let rootPub = "026655feed4d214c261e0a6b554395596f1f1476a77d999560e5a8df9b8a1a3515"
    private static let chainCode = "c9f3a1b2d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee"
    private static let testKey = "0123456789012345678901234567890123456789012345678901234567890123"

    func testDerivesMainAndTradingAddressesLikeBip32() throws {
        let main = try XCTUnwrap(PerpsDerivedAccount.derive(.main, rootPubKeyECDSA: Self.rootPub, hexChainCode: Self.chainCode))
        XCTAssertEqual(main.publicKey, "02f50e065bb0247361400347e5a08957da03e37686e78887991e78895015c0fcc3")
        XCTAssertEqual(main.address, "0xb98df75e8c9b4de5d3368e95553eb029345b8376")
        let trading = try XCTUnwrap(PerpsDerivedAccount.derive(.trading, rootPubKeyECDSA: Self.rootPub, hexChainCode: Self.chainCode))
        XCTAssertEqual(trading.publicKey, "02fcafbbc57b35ad724e4cde91692fb5009ba62cc0e92df298c09e086fc3bd88bc")
        XCTAssertEqual(trading.address, "0x1185457adb9913df15c0cfac2441986520827ce0")
        XCTAssertNotEqual(main.address, trading.address)
    }

    func testMainPathMatchesTheAppsEthereumDerivation() {
        XCTAssertEqual(PerpsSignerAccount.main.derivationPath, CoinType.ethereum.derivationPath())
    }

    func testInvalidRootKeyDerivesNothing() {
        XCTAssertNil(PerpsDerivedAccount.derive(.trading, rootPubKeyECDSA: "zz", hexChainCode: Self.chainCode))
    }

    // MARK: - Signer guard

    private func signed(_ request: HLExchangeRequest) throws -> (HLExchangeRequest, String) {
        let key = try XCTUnwrap(PrivateKey(data: try XCTUnwrap(Data(hexString: Self.testKey))))
        let address = PerpsSignerGuard.address(of: key.getPublicKeySecp256k1(compressed: true))
        let signature = try XCTUnwrap(HLSignature(recoverable: try XCTUnwrap(key.sign(digest: request.digest, curve: .secp256k1))))
        return (try request.signed(signature, expected: address), address)
    }

    func testGuardAcceptsTheExpectedSigner() throws {
        let request = try HLExchangeRequest.l1(.cancel, action: HLActions.cancel([(0, 1)]), nonce: 1, isMainnet: true)
        let (signedRequest, address) = try signed(request)
        XCTAssertNoThrow(try signedRequest.verifySigner(expected: address.uppercased().replacingOccurrences(of: "0X", with: "0x")))
    }

    /// The fallback the guard exists for: signed as main while trading was meant.
    func testGuardRefusesAnotherSigner() throws {
        let signedAction = try HLUserSignedAction.withdraw3(destination: "0x5e9ee1089755c3435139848e47e6635505d5a13a", amount: 10,
                                                            nonce: 1, isMainnet: true)
        let (signedRequest, address) = try signed(.userSigned(.withdraw3, signedAction))
        let trading = "0x1185457adb9913df15c0cfac2441986520827ce0"
        XCTAssertThrowsError(try signedRequest.verifySigner(expected: trading)) { error in
            XCTAssertEqual(error as? PerpsSignerGuardError, .signerMismatch(expected: trading, recovered: address))
        }
    }

    func testGuardRefusesAnUnsignedDryRunBody() throws {
        let request = try HLExchangeRequest.l1(.cancel, action: HLActions.cancel([(0, 1)]), nonce: 1, isMainnet: true)
        XCTAssertThrowsError(try request.verifySigner(expected: "0x1185457adb9913df15c0cfac2441986520827ce0")) { error in
            XCTAssertEqual(error as? PerpsSignerGuardError, .notSigned)
        }
    }

    /// The SDK renders r/s without leading zeros; recovery must still work.
    func testGuardHandlesMinimalHexSignatures() throws {
        let request = try HLExchangeRequest.l1(.cancel, action: HLActions.cancel([(0, 1)]), nonce: 1, isMainnet: true)
        let (signedRequest, address) = try signed(request)
        guard case .signed(let verified) = signedRequest.signature else { return XCTFail("signed") }
        let signature = verified.signature
        let minimal = HLSignature(r: HLExchangeSignature.minimalHex(signature.r), s: HLExchangeSignature.minimalHex(signature.s), v: signature.v)
        XCTAssertNoThrow(try PerpsSignerGuard.verify(digest: request.digest, signature: minimal, expected: address))
    }
}
