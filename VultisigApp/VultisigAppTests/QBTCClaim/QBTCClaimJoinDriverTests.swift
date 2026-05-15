//
//  QBTCClaimJoinDriverTests.swift
//  VultisigAppTests
//
//  Regression net for the single-session migration on the peer side.
//  Asserts the join driver registers and awaits on the constructor
//  session (no derive-per-round). Mocks `awaitKeysignStart` to throw
//  so the DKLS call is never reached.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimJoinDriverTests: XCTestCase {

    private static let testSession = KeysignSessionInfo(
        sessionId: "session-id-from-qr",
        encryptionKeyHex: String(repeating: "ab", count: 32),
        serviceName: "Vultisig-Test",
        localPartyId: "iPhone-B",
        serverAddr: "https://relay.vultisig.test"
    )

    private static let context = QBTCClaimContext(claimerAddress: "qbtc1abc")

    /// Returns a vault that has a Bitcoin coin with a valid 33-byte
    /// compressed pubkey so `QBTCClaimHashes.computeAll` succeeds — the
    /// driver fails fast otherwise and we never reach the session methods.
    private func makeVault() -> Vault {
        let vault = Vault(name: "TestVault")
        let btcAsset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        let btcCoin = Coin(
            asset: btcAsset,
            address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
            hexPublicKey: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        )
        vault.coins = [btcCoin]
        return vault
    }

    func testRunRegistersAndAwaitsOnConstructorSession() async {
        let service = MockKeysignSessionService()
        // Let `registerAsParticipant` succeed; trip `awaitKeysignStart`
        // to short-circuit the flow before DKLS is built.
        service.awaitError = MockSessionServiceError(message: "short-circuit before DKLS")

        let driver = QBTCClaimJoinDriver(
            vault: makeVault(),
            context: Self.context,
            session: Self.testSession,
            sessionService: service
        )

        await driver.run()

        XCTAssertEqual(service.calls.count, 2)
        XCTAssertEqual(
            service.calls.first,
            .registerAsParticipant(session: Self.testSession),
            "Driver must register on the constructor session — no derive-per-round"
        )
        XCTAssertEqual(
            service.calls.last,
            .awaitKeysignStart(session: Self.testSession, timeout: QBTCClaimJoinDriver.kickoffTimeoutSeconds),
            "Driver must await kickoff on the constructor session — no derive-per-round"
        )

        if case .failed = driver.phase {
            // ok — the error transitioned the phase as expected
        } else {
            XCTFail("expected `.failed`, got \(driver.phase)")
        }
    }
}
