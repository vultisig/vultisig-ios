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

    /// Returns a vault that has BTC + QBTC coins. BTC carries a valid
    /// 33-byte compressed pubkey so `QBTCClaimHashes.computeAll` succeeds;
    /// QBTC carries the claimer address the peer now derives from the
    /// vault (replacing the round-tripped `QBTCClaimContext`). The driver
    /// fails fast on either missing — we never reach the session methods.
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
        let qbtcAsset = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "qbtc",
            contractAddress: "",
            isNativeToken: true
        )
        let qbtcCoin = Coin(
            asset: qbtcAsset,
            address: "qbtc1abc",
            hexPublicKey: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        )
        vault.coins = [btcCoin, qbtcCoin]
        return vault
    }

    func testRunRegistersAndAwaitsOnConstructorSession() async {
        let service = MockKeysignSessionService()
        // Let `registerAsParticipant` succeed; trip `awaitKeysignStart`
        // to short-circuit the flow before DKLS is built.
        service.awaitError = MockSessionServiceError(message: "short-circuit before DKLS")

        let driver = QBTCClaimJoinDriver(
            vault: makeVault(),
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
