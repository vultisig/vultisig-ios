//
//  KeysignDerivationTests.swift
//  VultisigAppTests
//
//  The keysign derivation-path override: refusals (fail-closed), the default
//  branches staying exactly what the call sites computed before, and the
//  post-sign recovery check. Vectors use a fictional root key (the Python
//  SDK's public test key, chain code c9f3…) and signatures made with child
//  PRIVATE keys derived by @scure/bip32
//  (scratchpad/perps/vectors/gen_trading_signatures.mjs).
//

import Tss
import WalletCore
import XCTest
@testable import VultisigApp

final class KeysignDerivationTests: XCTestCase {
    private static let rootPub = "026655feed4d214c261e0a6b554395596f1f1476a77d999560e5a8df9b8a1a3515"
    private static let chainCode = "c9f3a1b2d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee"
    private static let tradingPub = "02fcafbbc57b35ad724e4cde91692fb5009ba62cc0e92df298c09e086fc3bd88bc"
    private static let tradingAddress = "0x1185457adb9913df15c0cfac2441986520827ce0"
    private static let mainAddress = "0xb98df75e8c9b4de5d3368e95553eb029345b8376"
    private static let digest = "abd132aaa31fbcc061d12529458d129b7249adcc3cae29b92e9b4c279c2db52a"
    private static let tradingSig = (r: "5bce6ae87b769d7e564d2bb1cf00f26587d51b83e22673b131fd1b35b3c86a12",
                                     s: "24638b70d05e9deb883a1f0aace71bdb363a4e760eec03d7351c37c0e00d05a5", v: 27)
    private static let mainSig = (r: "9f8475514753e252e0a8ef3a7750e459e8bbd1881898af27971642b1e83b5f5e",
                                  s: "1eb3ed499e999f0e7315069bec2ec9003c58634ae23d07a36d73b69047766c60", v: 28)

    private func payload(chain: String = "Ethereum", derivePath: String? = KeysignDerivationResolver.tradingAccountPath) throws -> CustomMessagePayload {
        let typed = try HLUserSignedAction.approveAgent(agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: "vultisig",
                                                        nonce: 1, isMainnet: true)
        var payload = CustomMessagePayload(method: "eth_signTypedData_v4", message: typed.typedData.signTypedDataV4JSON,
                                           vaultPublicKeyECDSA: Self.rootPub, vaultLocalPartyID: "iphone", chain: chain)
        payload.derivePath = derivePath
        return payload
    }

    private func resolve(_ payload: CustomMessagePayload?, libType: LibType? = .DKLS, keyType: KeyType = .ECDSA,
                         hasKeysignPayload: Bool = false) throws -> KeysignDerivation? {
        try KeysignDerivationResolver.override(libType: libType, rootPublicKeyECDSA: Self.rootPub, hexChainCode: Self.chainCode,
                                               keysignType: keyType, hasKeysignPayload: hasKeysignPayload, customMessagePayload: payload)
    }

    // MARK: Override

    func testNoOverrideWithoutDerivePath() throws {
        XCTAssertNil(try resolve(try payload(derivePath: nil)))
        XCTAssertNil(try resolve(nil))
    }

    func testTradingOverrideResolvesTheFictionalVector() throws {
        let derivation = try XCTUnwrap(try resolve(try payload()))
        XCTAssertEqual(derivation.dklsChainPath, "m/44'/60'/0'/0/1000")
        XCTAssertEqual(derivation.derivePath, "m/44'/60'/0'/0/1000")
        XCTAssertEqual(derivation.expectedPublicKeyHex, Self.tradingPub)
        let key = try XCTUnwrap(PublicKey(data: try XCTUnwrap(Data(hexString: derivation.expectedPublicKeyHex)), type: .secp256k1))
        XCTAssertEqual(PerpsSignerGuard.address(of: key), Self.tradingAddress)
    }

    func testCeremoniesRefuseAnOverrideUntilJoinersCarryThePath() throws {
        XCTAssertFalse(KeysignDerivationResolver.isCeremonyOverrideEnabled)
        let derivation = try resolve(try payload())
        XCTAssertThrowsError(try KeysignDerivationResolver.gateCeremony(derivation)) { error in
            XCTAssertEqual(error as? KeysignDerivationError, .ceremonyNotSupported)
        }
        // No override: every existing keysign passes the gate untouched.
        XCTAssertNoThrow(try KeysignDerivationResolver.gateCeremony(nil))
        XCTAssertNoThrow(try KeysignDerivationResolver.gateCeremony(derivation, enabled: true))
    }

    func testOverrideRefusesUnsupportedVaultsKeysAndChains() throws {
        let trading = try payload()
        for libType in [LibType.GG20, .KeyImport, nil] as [LibType?] {
            XCTAssertThrowsError(try resolve(trading, libType: libType)) {
                XCTAssertEqual($0 as? KeysignDerivationError, .unsupportedVaultType)
            }
        }
        XCTAssertThrowsError(try resolve(trading, keyType: .EdDSA)) { XCTAssertEqual($0 as? KeysignDerivationError, .unsupportedKeyType) }
        XCTAssertThrowsError(try resolve(trading, hasKeysignPayload: true)) { XCTAssertEqual($0 as? KeysignDerivationError, .unsupportedChain) }
        XCTAssertThrowsError(try resolve(try payload(chain: "Solana"))) { XCTAssertEqual($0 as? KeysignDerivationError, .unsupportedChain) }
    }

    func testOverrideRefusesPathsOutsideTheAllowlist() throws {
        for path in ["", " m/44'/60'/0'/0/1000", "m/44'/60'/0'/0/2147483648", "m/44'/60'/0'/0/1001", "m//1", "m/44'/60'/0'/0/0"] {
            XCTAssertThrowsError(try resolve(try payload(derivePath: path)), path) {
                XCTAssertEqual($0 as? KeysignDerivationError, .pathNotAllowed(path))
            }
        }
        XCTAssertTrue(KeysignDerivationResolver.isWellFormed("m/44'/60'/0'/0/1000"))
        XCTAssertFalse(KeysignDerivationResolver.isWellFormed("m/44'/60'/0'/0/2147483648"))
    }

    // MARK: Default branches are unchanged

    func testDefaultBranchesMatchThePreviousExpressions() throws {
        XCTAssertEqual(KeysignDerivationResolver.gg20DerivePath(keysignPayload: nil, override: nil),
                       TokensStore.Token.ethereum.coinType.derivationPath())
        for chain in Chain.allCases {
            let custom = try payload(chain: chain.name, derivePath: nil)
            guard let resolved = try? custom.resolveSigningChain() else { continue }
            XCTAssertEqual(try KeysignDerivationResolver.dklsChainPath(keysignPayload: nil, customMessagePayload: custom, isImport: false, override: nil),
                           resolved.coinType.derivationPath(), chain.name)
            XCTAssertEqual(try KeysignDerivationResolver.dklsChainPath(keysignPayload: nil, customMessagePayload: custom, isImport: true, override: nil),
                           "", chain.name)
        }
        XCTAssertThrowsError(try KeysignDerivationResolver.dklsChainPath(keysignPayload: nil, customMessagePayload: nil, isImport: false, override: nil))
    }

    // MARK: Post-sign recovery

    private func response(_ sig: (r: String, s: String, v: Int)) -> TssKeysignResponse {
        let resp = TssKeysignResponse()
        resp.r = sig.r
        resp.s = sig.s
        resp.recoveryID = String(format: "%02x", sig.v - 27)
        return resp
    }

    func testRecoveryAcceptsATradingKeySignature() {
        XCTAssertNoThrow(try KeysignDerivationResolver.verify(signatures: [Self.digest: response(Self.tradingSig)],
                                                              expectedPublicKeyHex: Self.tradingPub))
    }

    /// The silent-fallback case: the main key signed while the trading account was meant.
    func testRecoveryRejectsAMainKeySignature() {
        XCTAssertThrowsError(try KeysignDerivationResolver.verify(signatures: [Self.digest: response(Self.mainSig)],
                                                                  expectedPublicKeyHex: Self.tradingPub)) {
            XCTAssertEqual($0 as? KeysignDerivationError, .signerMismatch)
        }
    }

    // MARK: Perps wiring

    func testPerpsGuardSeparatesTradingFromMain() throws {
        let digest = try XCTUnwrap(Data(hexString: Self.digest))
        let trading = HLSignature(r: "0x" + Self.tradingSig.r, s: "0x" + Self.tradingSig.s, v: Self.tradingSig.v)
        let main = HLSignature(r: "0x" + Self.mainSig.r, s: "0x" + Self.mainSig.s, v: Self.mainSig.v)
        XCTAssertEqual(try PerpsSignerGuard.verify(digest: digest, signature: trading, expected: Self.tradingAddress).signer, Self.tradingAddress)
        XCTAssertEqual(try PerpsSignerGuard.verify(digest: digest, signature: main, expected: Self.mainAddress).signer, Self.mainAddress)
        XCTAssertThrowsError(try PerpsSignerGuard.verify(digest: digest, signature: main, expected: Self.tradingAddress)) {
            XCTAssertEqual($0 as? PerpsSignerGuardError, .signerMismatch(expected: Self.tradingAddress, recovered: Self.mainAddress))
        }
    }

    func testVaultSignerSetsThePathOnlyForTheTradingAccount() throws {
        let request = PerpsSignRequest.l1(action: HLActions.cancel([(0, 1)]), nonce: 1, isMainnet: true, vaultAddress: nil)
        guard case let .vaultKeysign(trading, tradingDigest) = try VaultPerpsSigner(vaultPublicKeyECDSA: Self.rootPub, vaultLocalPartyID: "a",
                                                                                     account: .trading).prepare(request),
              case let .vaultKeysign(main, mainDigest) = try VaultPerpsSigner(vaultPublicKeyECDSA: Self.rootPub, vaultLocalPartyID: "a").prepare(request)
        else { return XCTFail("expected keysign payloads") }
        XCTAssertEqual(trading.derivePath, "m/44'/60'/0'/0/1000")
        XCTAssertNil(main.derivePath, "main-path payloads encode exactly as before")
        XCTAssertEqual(trading.keysignMessages, main.keysignMessages, "the path never feeds the digest")
        XCTAssertEqual(tradingDigest, mainDigest)
    }
}
