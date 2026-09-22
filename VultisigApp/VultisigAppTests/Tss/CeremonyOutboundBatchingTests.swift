//
//  CeremonyOutboundBatchingTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import Mediator
import XCTest
import godkls
import goschnorr
import vscore

/// Drives the real ceremony libraries against a recording relay. Building a setup
/// message, opening a session and draining its first outbound round are all local
/// operations, so the loop under test runs without a peer or a relay.
///
/// The expected receivers of each body are read back from the library rather than
/// assumed, so the assertions stay honest if a round's addressing ever changes.
@MainActor
final class CeremonyOutboundBatchingTests: XCTestCase {

    private static let encryptionKey = String(repeating: "ab", count: 32)
    private static let localParty = "partyA"

    // MARK: - DKLS (ECDSA) keygen

    func testDKLSKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertDKLSKeygenBatchesEachBody(committee: ["partyA", "partyB", "partyC"])
    }

    func testDKLSKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertDKLSKeygenBatchesEachBody(committee: ["partyA", "partyB"])
    }

    // MARK: - Schnorr (EdDSA) keygen — the loop that skips an empty slot instead of breaking

    func testSchnorrKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertSchnorrKeygenBatchesEachBody(committee: ["partyA", "partyB", "partyC"])
    }

    func testSchnorrKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertSchnorrKeygenBatchesEachBody(committee: ["partyA", "partyB"])
    }

    // MARK: - ML-DSA keygen

    func testDilithiumKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertDilithiumKeygenBatchesEachBody(committee: ["partyA", "partyB", "partyC"])
    }

    func testDilithiumKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertDilithiumKeygenBatchesEachBody(committee: ["partyA", "partyB"])
    }

    // MARK: - DKLS

    private func assertDKLSKeygenBatchesEachBody(
        committee: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let relay = RecordingRelayClient()
        let keygen = DKLSKeygen(
            vault: Self.makeVault(),
            tssType: .Keygen,
            keygenCommittee: committee,
            vaultOldCommittee: [],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            encryptionKeyHex: Self.encryptionKey,
            isInitiateDevice: true,
            localUI: nil,
            httpClient: relay
        )

        var buf = godkls.tss_buffer()
        defer { godkls.tss_buffer_free(&buf) }
        let idBytes = DKLSHelper.arrayToBytes(parties: committee)
        var ids = idBytes.to_dkls_goslice()
        let setupResult = dkls_keygen_setupmsg_new(
            DKLSHelper.getThreshod(input: committee.count),
            nil,
            &ids,
            &buf
        )
        XCTAssertEqual(setupResult, godkls.lib_error(0), "setup message", file: file, line: line)
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        var decodedSetup = setup.to_dkls_goslice()
        let localPartyBytes = Self.localParty.toArray()
        var localPartySlice = localPartyBytes.to_dkls_goslice()
        var handle = godkls.Handle()
        let sessionResult = dkls_keygen_session_from_setup(&decodedSetup, &localPartySlice, &handle)
        XCTAssertEqual(sessionResult, godkls.lib_error(0), "session", file: file, line: line)
        defer { _ = dkls_keygen_session_free(&handle) }

        try await keygen.processDKLSOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(relay.sentMessages, file: file, line: line) { bodyBytes in
            let slice = bodyBytes.to_dkls_goslice()
            return Self.collect(count: committee.count) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    // MARK: - Schnorr

    private func assertSchnorrKeygenBatchesEachBody(
        committee: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var buf = goschnorr.tss_buffer()
        defer { goschnorr.tss_buffer_free(&buf) }
        let idBytes = DKLSHelper.arrayToBytes(parties: committee)
        var ids = idBytes.to_dkls_goslice()
        let setupResult = schnorr_keygen_setupmsg_new(
            DKLSHelper.getThreshod(input: committee.count),
            nil,
            &ids,
            &buf
        )
        XCTAssertEqual(setupResult, .schnorrLibOK, "setup message", file: file, line: line)
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        let relay = RecordingRelayClient()
        let keygen = SchnorrKeygen(
            vault: Self.makeVault(),
            tssType: .Keygen,
            keygenCommittee: committee,
            vaultOldCommittee: [],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            encryptionKeyHex: Self.encryptionKey,
            isInitiatedDevice: true,
            setupMessage: setup,
            localUI: nil,
            httpClient: relay
        )

        var decodedSetup = setup.to_dkls_goslice()
        let localPartyBytes = Self.localParty.toArray()
        var localPartySlice = localPartyBytes.to_dkls_goslice()
        var handle = goschnorr.Handle()
        let sessionResult = schnorr_keygen_session_from_setup(&decodedSetup, &localPartySlice, &handle)
        XCTAssertEqual(sessionResult, .schnorrLibOK, "session", file: file, line: line)
        defer { schnorr_keygen_session_free(&handle) }

        try await keygen.processSchnorrOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(relay.sentMessages, file: file, line: line) { bodyBytes in
            let slice = bodyBytes.to_dkls_goslice()
            return Self.collect(count: committee.count) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    // MARK: - ML-DSA

    private func assertDilithiumKeygenBatchesEachBody(
        committee: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var buf = vscore.tss_buffer()
        defer { vscore.tss_buffer_free(&buf) }
        let idBytes = DKLSHelper.arrayToBytes(parties: committee)
        var ids = idBytes.to_mldsa_goslice()
        let setupResult = mldsa_keygen_setupmsg_new(
            vscore.MlDsa44,
            DKLSHelper.getThreshod(input: committee.count),
            nil,
            &ids,
            &buf
        )
        XCTAssertEqual(setupResult, vscore.mldsa_error(0), "setup message", file: file, line: line)
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        let relay = RecordingRelayClient()
        let keygen = DilithiumKeygen(
            vault: Self.makeVault(),
            tssType: .Keygen,
            keygenCommittee: committee,
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            encryptionKeyHex: Self.encryptionKey,
            isInitiateDevice: true,
            setupMessage: setup,
            httpClient: relay
        )

        var decodedSetup = setup.to_mldsa_goslice()
        let localPartyBytes = Self.localParty.toArray()
        var localPartySlice = localPartyBytes.to_mldsa_goslice()
        var handle = vscore.Handle()
        let sessionResult = mldsa_keygen_session_from_setup(
            vscore.MlDsa44,
            &decodedSetup,
            &localPartySlice,
            &handle
        )
        XCTAssertEqual(sessionResult, vscore.mldsa_error(0), "session", file: file, line: line)
        defer { _ = mldsa_keygen_session_free(handle) }

        try await keygen.processDilithiumOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(relay.sentMessages, file: file, line: line) { bodyBytes in
            let slice = bodyBytes.to_mldsa_goslice()
            return Self.collect(count: committee.count) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    // MARK: - Shared assertions

    /// Fails unless the ceremony produced one relay request per outbound body, each
    /// addressed to exactly the receivers `expectedReceivers` reads back from the library.
    private static func assertOneRequestPerBody(
        _ requests: [Message],
        file: StaticString,
        line: UInt,
        expectedReceivers: ([UInt8]) -> [String]
    ) throws {
        XCTAssertFalse(requests.isEmpty, "the ceremony sent nothing", file: file, line: line)
        XCTAssertEqual(
            Set(requests.map(\.hash)).count,
            requests.count,
            "a body was split across more than one request",
            file: file,
            line: line
        )

        for request in requests {
            let plaintext = try XCTUnwrap(
                request.body.aesDecryptGCM(key: encryptionKey),
                file: file,
                line: line
            )
            let bodyBytes = [UInt8](try XCTUnwrap(Data(base64Encoded: plaintext), file: file, line: line))
            XCTAssertEqual(request.from, localParty, file: file, line: line)
            XCTAssertEqual(request.to, expectedReceivers(bodyBytes), file: file, line: line)
        }
    }

    private static func collect(count: Int, receiver: (UInt32) -> [UInt8]) -> [String] {
        var receivers: [String] = []
        for idx in 0..<count {
            let bytes = receiver(UInt32(idx))
            if bytes.isEmpty {
                break
            }
            receivers.append(String(bytes: bytes, encoding: .utf8)!)
        }
        return receivers
    }

    private static func makeVault() -> Vault {
        let vault = Vault(name: "batching", libType: .DKLS)
        vault.localPartyID = localParty
        return vault
    }
}

/// Accepts every relay POST and keeps the message it carried.
private final class RecordingRelayClient: HTTPClientProtocol, @unchecked Sendable {
    private(set) var sentMessages: [Message] = []

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        if let relay = target as? TssRelayAPI, case .sendMessage(_, let message, _, _) = relay.endpoint {
            sentMessages.append(message)
        }
        let url = URL(string: "https://relay.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(), response: response)
    }
}
