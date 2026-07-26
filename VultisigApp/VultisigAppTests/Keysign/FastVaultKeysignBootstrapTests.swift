//
//  FastVaultKeysignBootstrapTests.swift
//  VultisigAppTests
//
//  Covers the off-screen fast-vault session bootstrap: it must run the
//  relay calls in the QBTC-proven order (register -> wake -> await ->
//  kickoff) and assemble a `KeysignInput` whose committee/session fields
//  come from the joined peers + the provisioned session. Uses the
//  custom-message path so message generation is pure (no relay / no
//  chain RPC) and the assertions stay deterministic.
//

@testable import VultisigApp
import XCTest

@MainActor
final class FastVaultKeysignBootstrapTests: XCTestCase {

    private static let session = KeysignSessionInfo(
        sessionId: "session-abc",
        encryptionKeyHex: String(repeating: "ab", count: 32),
        serviceName: "Vultisig-Test",
        localPartyId: "iPhone-A",
        serverAddr: "https://relay.vultisig.test"
    )

    private static let participants = ["iPhone-A", "server-1"]

    private func makeVaultWithEthereum() -> Vault {
        let vault = Vault(name: "TestVault")
        let ethCoin = Coin(
            asset: CoinMeta(
                chain: .ethereum,
                ticker: "ETH",
                logo: "eth",
                decimals: 18,
                priceProviderId: "ethereum",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "0x0000000000000000000000000000000000000000",
            hexPublicKey: "04"
        )
        vault.coins = [ethCoin]
        return vault
    }

    private func makeCustomMessagePayload(for vault: Vault) -> CustomMessagePayload {
        CustomMessagePayload(
            method: "personal_sign",
            message: "0xdeadbeef",
            vaultPublicKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            chain: Chain.ethereum.name,
            decodedMessage: nil
        )
    }

    func testMakeKeysignInputRunsBootstrapInOrderAndAssemblesInput() async throws {
        let mock = MockFastVaultSessionProvider(session: Self.session, participants: Self.participants)
        let vault = makeVaultWithEthereum()
        let payload = makeCustomMessagePayload(for: vault)
        let bootstrap = FastVaultKeysignBootstrap(sessionService: mock)

        let input = try await bootstrap.makeKeysignInput(
            vault: vault,
            keysignPayload: nil,
            customMessagePayload: payload,
            fastVaultPassword: "hunter2"
        )

        // Bootstrap must register on the relay BEFORE waking Vultiserver,
        // then await the peer, then kick off — the QBTC-proven order.
        XCTAssertEqual(
            mock.calls.map(\.name),
            ["newSession", "register", "wake", "awaitPeer", "kickoff"]
        )

        // Committee + session identity flow from the joined peers and the
        // provisioned session, not from anything the caller built up front.
        XCTAssertEqual(input.keysignCommittee, Self.participants)
        XCTAssertEqual(input.sessionID, Self.session.sessionId)
        XCTAssertEqual(input.mediatorURL, Self.session.serverAddr)
        XCTAssertEqual(input.encryptionKeyHex, Self.session.encryptionKeyHex)
        XCTAssertTrue(input.isInitiateDevice)
        XCTAssertNil(input.keysignPayload)
        XCTAssertEqual(input.customMessagePayload, payload)
        XCTAssertEqual(input.messsageToSign, payload.keysignMessages)
        XCTAssertFalse(input.messsageToSign.isEmpty)
        if case .ECDSA = input.keysignType {} else {
            XCTFail("Custom-message (Ethereum) signing should use ECDSA, got \(input.keysignType)")
        }

        // The wake POST must carry the same messages + coin metadata.
        XCTAssertEqual(mock.wakeMessages, payload.keysignMessages)
        XCTAssertEqual(mock.wakeChain, Chain.ethereum.name)
        XCTAssertEqual(mock.wakeVaultPassword, "hunter2")
        XCTAssertEqual(mock.wakeIsECDSA, true)
        XCTAssertEqual(mock.wakeIsMldsa, false)

        // The committee we kick off with is exactly the awaited peer set.
        XCTAssertEqual(mock.kickoffParticipants, Self.participants)
    }

    func testMakeKeysignInputPropagatesPeerTimeout() async {
        let mock = MockFastVaultSessionProvider(session: Self.session, participants: Self.participants)
        mock.awaitError = KeysignSessionServiceError.fastVaultPeerTimeout
        let vault = makeVaultWithEthereum()
        let payload = makeCustomMessagePayload(for: vault)
        let bootstrap = FastVaultKeysignBootstrap(sessionService: mock)

        do {
            _ = try await bootstrap.makeKeysignInput(
                vault: vault,
                keysignPayload: nil,
                customMessagePayload: payload,
                fastVaultPassword: "hunter2"
            )
            XCTFail("Expected the peer timeout to propagate")
        } catch {
            // Kickoff must not run once the peer never joined.
            XCTAssertFalse(mock.calls.map(\.name).contains("kickoff"))
        }
    }

    func testMakeKeysignInputThrowsWhenNothingToSign() async {
        let mock = MockFastVaultSessionProvider(session: Self.session, participants: Self.participants)
        let vault = makeVaultWithEthereum()
        let bootstrap = FastVaultKeysignBootstrap(sessionService: mock)

        do {
            _ = try await bootstrap.makeKeysignInput(
                vault: vault,
                keysignPayload: nil,
                customMessagePayload: nil,
                fastVaultPassword: "hunter2"
            )
            XCTFail("Expected a missing-payload error")
        } catch let error as FastVaultKeysignBootstrapError {
            XCTAssertEqual(error, .missingPayload)
            XCTAssertTrue(mock.calls.map(\.name).allSatisfy { $0 == "newSession" })
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

extension FastVaultKeysignBootstrapError: Equatable {
    public static func == (lhs: FastVaultKeysignBootstrapError, rhs: FastVaultKeysignBootstrapError) -> Bool {
        switch (lhs, rhs) {
        case (.missingSigningCoin, .missingSigningCoin),
             (.noMessagesToSign, .noMessagesToSign),
             (.missingPayload, .missingPayload):
            return true
        default:
            return false
        }
    }
}

// swiftlint:disable async_without_await
@MainActor
private final class MockFastVaultSessionProvider: FastVaultKeysignSessionProviding {

    struct Call {
        let name: String
    }

    private(set) var calls: [Call] = []
    private let session: KeysignSessionInfo
    var participants: [String]
    var awaitError: Error?

    // Captured wake arguments for assertions.
    private(set) var wakeMessages: [String] = []
    private(set) var wakeChain: String = ""
    private(set) var wakeVaultPassword: String = ""
    private(set) var wakeIsECDSA: Bool = false
    private(set) var wakeIsMldsa: Bool = false
    private(set) var kickoffParticipants: [String] = []

    init(session: KeysignSessionInfo, participants: [String]) {
        self.session = session
        self.participants = participants
    }

    func newSession(vault _: Vault, serviceName _: String?) throws -> KeysignSessionInfo {
        calls.append(Call(name: "newSession"))
        return session
    }

    func registerAsParticipant(session _: KeysignSessionInfo) async throws {
        calls.append(Call(name: "register"))
    }

    func wakeFastVaultServer(
        publicKeyEcdsa _: String,
        keysignMessages: [String],
        session _: KeysignSessionInfo,
        derivePath _: String,
        isECDSA: Bool,
        vaultPassword: String,
        chain: String,
        isMldsa: Bool
    ) async throws {
        calls.append(Call(name: "wake"))
        wakeMessages = keysignMessages
        wakeChain = chain
        wakeVaultPassword = vaultPassword
        wakeIsECDSA = isECDSA
        wakeIsMldsa = isMldsa
    }

    func awaitFastVaultPeer(
        discovery _: ParticipantDiscovery,
        session _: KeysignSessionInfo,
        timeout _: TimeInterval
    ) async throws -> [String] {
        calls.append(Call(name: "awaitPeer"))
        if let awaitError { throw awaitError }
        return participants
    }

    func kickoffCommittee(session _: KeysignSessionInfo, participants: [String]) async throws {
        calls.append(Call(name: "kickoff"))
        kickoffParticipants = participants
    }
}

// swiftlint:enable async_without_await
