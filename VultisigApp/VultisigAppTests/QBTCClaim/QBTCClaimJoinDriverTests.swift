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

    /// Vault keys that derive a valid BTC (ECDSA) + QBTC (MLDSA) account
    /// on the fly, so the resolver succeeds even with empty `coins`.
    private static let pubKeyECDSA = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    private static let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
    private static let publicKeyMLDSA44 = String(repeating: "ab", count: 1312)

    /// Returns a vault that has BTC + QBTC coins. BTC carries a valid
    /// 33-byte compressed pubkey so `QBTCClaimHashes.computeAll` succeeds;
    /// QBTC carries the claimer address the peer derives from the vault
    /// (replacing the round-tripped `QBTCClaimContext`). With both coins
    /// enabled the resolver returns them as-is and the driver proceeds to
    /// the session methods.
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

    /// A quantum-capable vault with the BTC/QBTC chains NOT enabled — the
    /// resolver derives both accounts in-memory from these keys.
    private func makeQuantumVaultWithoutCoins() -> Vault {
        let vault = Vault(name: "TestVault")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.publicKeyMLDSA44 = Self.publicKeyMLDSA44
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

    /// Regression for #4679: a quantum vault without the BTC/QBTC chains
    /// enabled no longer fails fast — the driver derives both accounts and
    /// proceeds to the session methods (short-circuited here at kickoff).
    func testRunDerivesCoinsWhenChainsNotEnabled() async {
        let service = MockKeysignSessionService()
        service.awaitError = MockSessionServiceError(message: "short-circuit before DKLS")

        let driver = QBTCClaimJoinDriver(
            vault: makeQuantumVaultWithoutCoins(),
            session: Self.testSession,
            sessionService: service
        )

        await driver.run()

        XCTAssertEqual(
            service.calls.count, 2,
            "Driver must derive the coins and reach register + await — no fail-fast on missing coins"
        )
        XCTAssertNotNil(driver.resolvedCoins, "Driver should expose the derived coins")
        if case .failed = driver.phase {
            // ok — only the mocked kickoff error stopped the run, not a missing coin
        } else {
            XCTFail("expected `.failed`, got \(driver.phase)")
        }
    }
}
