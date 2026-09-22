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
/// message, opening a session and draining its outbound messages are all local
/// operations, so the loop under test runs without a peer or a relay.
///
/// Both sides of every assertion come from the library, never from an assumption
/// about what a given round looks like: a twin session counts the outbound bodies,
/// and the receivers of each body are read back per body.
@MainActor
final class CeremonyOutboundBatchingTests: XCTestCase {

    private static let encryptionKey = String(repeating: "ab", count: 32)
    private static let localParty = "partyA"

    // Each framework exports its own `LIB_OK`, which Swift cannot disambiguate
    // from the bare case name, so name the success value per library.
    private static let dklsOK = godkls.lib_error(rawValue: 0)
    private static let schnorrOK = goschnorr.schnorr_lib_error(rawValue: 0)
    private static let mldsaOK = vscore.mldsa_error(0)

    /// What a loop does when the library reports no receiver at an index.
    /// SchnorrKeygen skips the slot; every other loop stops walking the committee.
    private enum EmptySlot {
        case stop
        case skip
    }

    // MARK: - DKLS (ECDSA) keygen

    func testDKLSKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertDKLSKeygenBatchesEachBody(
            committee: ["partyA", "partyB", "partyC"],
            requiresMulticast: true
        )
    }

    func testDKLSKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertDKLSKeygenBatchesEachBody(
            committee: ["partyA", "partyB"],
            requiresMulticast: false
        )
    }

    // MARK: - Schnorr (EdDSA) keygen — the loop that skips an empty slot instead of stopping

    func testSchnorrKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertSchnorrKeygenBatchesEachBody(
            committee: ["partyA", "partyB", "partyC"],
            requiresMulticast: true
        )
    }

    func testSchnorrKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertSchnorrKeygenBatchesEachBody(
            committee: ["partyA", "partyB"],
            requiresMulticast: false
        )
    }

    // MARK: - ML-DSA keygen

    func testDilithiumKeygenSendsOneRequestPerOutboundBodyWithThreeParties() async throws {
        try await assertDilithiumKeygenBatchesEachBody(
            committee: ["partyA", "partyB", "partyC"],
            requiresMulticast: true
        )
    }

    func testDilithiumKeygenSendsOneRequestPerOutboundBodyWithTwoParties() async throws {
        try await assertDilithiumKeygenBatchesEachBody(
            committee: ["partyA", "partyB"],
            requiresMulticast: false
        )
    }

    // MARK: - DKLS

    private func assertDKLSKeygenBatchesEachBody(
        committee: [String],
        requiresMulticast: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let relay = RecordingRelayClient()
        let keygen = Self.makeDKLSKeygen(committee: committee, relay: relay)

        // A twin session on its own setup message says how many bodies this party
        // emits, which is what the number of requests has to match.
        var oracleHandle = try Self.dklsSession(committee: committee)
        defer { _ = dkls_keygen_session_free(&oracleHandle) }
        var expectedBodies = 0
        while true {
            // A drained session answers OK with an empty buffer; any other code is a
            // real failure that would otherwise look like the end of the round.
            let (result, body) = keygen.GetDKLSOutboundMessage(handle: oracleHandle)
            guard result == Self.dklsOK else {
                throw HelperError.runtimeError("dkls outbound message failed: \(result)")
            }
            if body.isEmpty { break }
            expectedBodies += 1
        }

        var handle = try Self.dklsSession(committee: committee)
        defer { _ = dkls_keygen_session_free(&handle) }
        try await keygen.processDKLSOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(
            relay.sentMessages,
            expectedBodies: expectedBodies,
            requiresMulticast: requiresMulticast,
            file: file,
            line: line
        ) { bodyBytes in
            let slice = bodyBytes.to_dkls_goslice()
            return Self.collect(count: committee.count, emptySlot: .stop) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    private static func makeDKLSKeygen(committee: [String], relay: RecordingRelayClient) -> DKLSKeygen {
        DKLSKeygen(
            vault: makeVault(),
            tssType: .Keygen,
            keygenCommittee: committee,
            vaultOldCommittee: [],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            encryptionKeyHex: encryptionKey,
            isInitiateDevice: true,
            localUI: nil,
            httpClient: relay
        )
    }

    private static func dklsSession(committee: [String]) throws -> godkls.Handle {
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
        guard setupResult == dklsOK else {
            throw HelperError.runtimeError("dkls setup message failed: \(setupResult)")
        }
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        var decodedSetup = setup.to_dkls_goslice()
        let localPartyBytes = localParty.toArray()
        var localPartySlice = localPartyBytes.to_dkls_goslice()
        var handle = godkls.Handle()
        let sessionResult = dkls_keygen_session_from_setup(&decodedSetup, &localPartySlice, &handle)
        guard sessionResult == dklsOK else {
            throw HelperError.runtimeError("dkls session failed: \(sessionResult)")
        }
        return handle
    }

    // MARK: - Schnorr

    private func assertSchnorrKeygenBatchesEachBody(
        committee: [String],
        requiresMulticast: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let relay = RecordingRelayClient()
        let (setup, handle) = try Self.schnorrSession(committee: committee)
        var handleToFree = handle
        defer { schnorr_keygen_session_free(&handleToFree) }
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

        var oracleHandle = try Self.schnorrSession(committee: committee).1
        defer { schnorr_keygen_session_free(&oracleHandle) }
        var expectedBodies = 0
        while true {
            let (result, body) = keygen.GetSchnorrOutboundMessage(handle: oracleHandle)
            guard result == Self.schnorrOK else {
                throw HelperError.runtimeError("schnorr outbound message failed: \(result)")
            }
            if body.isEmpty { break }
            expectedBodies += 1
        }

        try await keygen.processSchnorrOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(
            relay.sentMessages,
            expectedBodies: expectedBodies,
            requiresMulticast: requiresMulticast,
            file: file,
            line: line
        ) { bodyBytes in
            let slice = bodyBytes.to_dkls_goslice()
            // This loop skips an empty slot rather than stopping, so the oracle must too.
            return Self.collect(count: committee.count, emptySlot: .skip) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    private static func schnorrSession(committee: [String]) throws -> ([UInt8], goschnorr.Handle) {
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
        guard setupResult == schnorrOK else {
            throw HelperError.runtimeError("schnorr setup message failed: \(setupResult)")
        }
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        var decodedSetup = setup.to_dkls_goslice()
        let localPartyBytes = localParty.toArray()
        var localPartySlice = localPartyBytes.to_dkls_goslice()
        var handle = goschnorr.Handle()
        let sessionResult = schnorr_keygen_session_from_setup(&decodedSetup, &localPartySlice, &handle)
        guard sessionResult == schnorrOK else {
            throw HelperError.runtimeError("schnorr session failed: \(sessionResult)")
        }
        return (setup, handle)
    }

    // MARK: - ML-DSA

    private func assertDilithiumKeygenBatchesEachBody(
        committee: [String],
        requiresMulticast: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let relay = RecordingRelayClient()
        let (setup, handle) = try Self.dilithiumSession(committee: committee)
        defer { _ = mldsa_keygen_session_free(handle) }
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

        let oracleHandle = try Self.dilithiumSession(committee: committee).1
        defer { _ = mldsa_keygen_session_free(oracleHandle) }
        var expectedBodies = 0
        while true {
            let (result, body) = keygen.GetDilithiumOutboundMessage(handle: oracleHandle)
            guard result == Self.mldsaOK else {
                throw HelperError.runtimeError("mldsa outbound message failed: \(result)")
            }
            if body.isEmpty { break }
            expectedBodies += 1
        }

        try await keygen.processDilithiumOutboundMessage(handle: handle)

        try Self.assertOneRequestPerBody(
            relay.sentMessages,
            expectedBodies: expectedBodies,
            requiresMulticast: requiresMulticast,
            file: file,
            line: line
        ) { bodyBytes in
            let slice = bodyBytes.to_mldsa_goslice()
            return Self.collect(count: committee.count, emptySlot: .stop) { idx in
                keygen.getOutboundMessageReceiver(handle: handle, message: slice, idx: idx)
            }
        }
    }

    private static func dilithiumSession(committee: [String]) throws -> ([UInt8], vscore.Handle) {
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
        guard setupResult == mldsaOK else {
            throw HelperError.runtimeError("mldsa setup message failed: \(setupResult)")
        }
        let setup = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))

        var decodedSetup = setup.to_mldsa_goslice()
        let localPartyBytes = localParty.toArray()
        var localPartySlice = localPartyBytes.to_mldsa_goslice()
        var handle = vscore.Handle()
        let sessionResult = mldsa_keygen_session_from_setup(
            vscore.MlDsa44,
            &decodedSetup,
            &localPartySlice,
            &handle
        )
        guard sessionResult == mldsaOK else {
            throw HelperError.runtimeError("mldsa session failed: \(sessionResult)")
        }
        return (setup, handle)
    }

    // MARK: - Shared assertions

    /// Fails unless the ceremony produced exactly one relay request per outbound body,
    /// each addressed to exactly the receivers `expectedReceivers` reads back per body.
    ///
    /// `requiresMulticast` guards against a vacuous pass: with a single peer the serial
    /// loop and the batched one are indistinguishable, so a committee that should produce
    /// a multi-receiver body has to actually produce one for the run to prove anything.
    private static func assertOneRequestPerBody(
        _ requests: [Message],
        expectedBodies: Int,
        requiresMulticast: Bool,
        file: StaticString,
        line: UInt,
        expectedReceivers: ([UInt8]) -> [String]
    ) throws {
        XCTAssertGreaterThan(expectedBodies, 0, "the library emitted nothing to send", file: file, line: line)
        XCTAssertEqual(
            requests.count,
            expectedBodies,
            "expected one request per outbound body",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(requests.map(\.hash)).count,
            requests.count,
            "a body was split across more than one request",
            file: file,
            line: line
        )
        if requiresMulticast {
            XCTAssertTrue(
                requests.contains { $0.to.count > 1 },
                "no body reached more than one peer, so this run cannot distinguish batching",
                file: file,
                line: line
            )
        }

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

    private static func collect(
        count: Int,
        emptySlot: EmptySlot,
        receiver: (UInt32) -> [UInt8]
    ) -> [String] {
        var receivers: [String] = []
        for idx in 0..<count {
            let bytes = receiver(UInt32(idx))
            if bytes.isEmpty {
                switch emptySlot {
                case .stop:
                    return receivers
                case .skip:
                    continue
                }
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
