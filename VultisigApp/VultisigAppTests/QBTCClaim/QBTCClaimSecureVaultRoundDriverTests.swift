//
//  QBTCClaimSecureVaultRoundDriverTests.swift
//  VultisigAppTests
//
//  Regression net for the SecureVault driver. Asserts the driver does
//  NOT call any `KeysignSessionServicing` methods — the pair screen's
//  `KeysignDiscoveryView.startKeysign` already POSTed `/start/{sessionId}`
//  before the route pushed us here, so a second kickoff would 500.
//  DKLSKeysign itself isn't testable inline (covered by manual end-to-
//  end per `QBTCClaimRoundRunner` comment).
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimSecureVaultRoundDriverTests: XCTestCase {

    private static let testSession = KeysignSessionInfo(
        sessionId: "session-id-from-qr",
        encryptionKeyHex: String(repeating: "ab", count: 32),
        serviceName: "Vultisig-Test",
        localPartyId: "iPhone-A",
        serverAddr: "https://relay.vultisig.test"
    )

    private static let participants = ["iPhone-A", "iPhone-B"]

    private static let testInput = QBTCClaimBtcRoundInput(
        vault: Vault(name: "TestVault"),
        btcCoin: Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: "bitcoin",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
            hexPublicKey: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        ),
        messageHashHex: String(repeating: "cd", count: 32),
        fastVaultPassword: ""
    )

    func testRunBtcRoundDoesNotReKickoff() async {
        // If the driver re-kicks off, the relay returns 500 because the
        // pair screen's `KeysignDiscoveryView` already started the
        // session. Trip every session-service knob so the test fails
        // loudly if the driver regresses to calling any of them.
        let service = MockKeysignSessionService()
        let trip = MockSessionServiceError(message: "driver must not call session service")
        service.registerError = trip
        service.kickoffError = trip
        service.awaitError = trip

        let driver = QBTCClaimSecureVaultRoundDriver(
            session: Self.testSession,
            participants: Self.participants,
            sessionService: service
        )

        // We expect the call to reach DKLS and fail there (no relay
        // available in tests). The assertion of interest is the recorded
        // session-service call count, not the throw site.
        _ = try? await driver.runBtcRound(input: Self.testInput)

        XCTAssertTrue(
            service.calls.isEmpty,
            "SecureVault driver must not call any KeysignSessionServicing methods; got \(service.calls)"
        )
    }
}
