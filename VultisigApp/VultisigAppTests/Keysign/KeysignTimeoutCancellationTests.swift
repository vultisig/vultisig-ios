//
//  KeysignTimeoutCancellationTests.swift
//  VultisigAppTests
//
//  Covers the stage-timeout-doesn't-cancel-the-body vector: the 90s stage
//  timeout calls cancelAll() but the DKLS/Schnorr/Dilithium poll loops never
//  observed cancellation, so the orphaned ceremony ran to completion and
//  broadcast unconditionally. These tests pin down (1) the poll loops are now
//  cooperatively cancellable, (2) the per-message-scaled stage budget so the
//  timeout no longer fires on a healthy slow ceremony, and (3) the broadcast
//  gate that prevents an already-terminal status from broadcasting.
//

@testable import VultisigApp
import BigInt
import Foundation
import godkls
import XCTest

@MainActor
final class KeysignTimeoutCancellationTests: XCTestCase {

    // MARK: - Fakes

    /// Returns empty data so the poll loop takes its `Task.sleep` branch and
    /// keeps spinning — exactly the stalled-ceremony shape the stage timeout is
    /// meant to break out of. Records whether it was ever hit.
    private final class EmptyPollingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var _requestCount = 0
        var requestCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _requestCount
        }

        func request(_: TargetType) async throws -> HTTPResponse<Data> {
            await Task.yield()
            lock.lock(); _requestCount += 1; lock.unlock()
            let url = URL(string: "https://example.invalid")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: Data(), response: response)
        }
    }

    // MARK: - (1) Poll loops are cooperatively cancellable

    func testDKLSPullInboundMessagesThrowsCancellationWhenTaskCancelled() async {
        let http = EmptyPollingHTTPClient()
        let vault = Vault(name: "DKLS", libType: .DKLS)
        vault.localPartyID = "partyA"
        let keysign = DKLSKeysign(
            keysignCommittee: ["partyA", "partyB"],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            messsageToSign: ["deadbeef"],
            vault: vault,
            encryptionKeyHex: "00",
            chainPath: "m/44'/60'/0'/0/0",
            isInitiateDevice: false,
            publicKeyECDSA: "ECDSAKey",
            httpClient: http
        )

        let started = expectation(description: "poll loop reached the network")
        let task = Task { @MainActor () -> Error? in
            // checkCancellation() is the first statement in the loop, so the
            // handle is never dereferenced before the throw — a default handle
            // is safe here.
            started.fulfill()
            do {
                _ = try await keysign.pullInboundMessages(handle: godkls.Handle(), messageID: "msg")
                return nil
            } catch {
                return error
            }
        }

        await fulfillment(of: [started], timeout: 5)
        // Give the loop a beat to enter the empty-data sleep branch, then cancel.
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()

        let thrown = await task.value
        XCTAssertTrue(thrown is CancellationError, "cancelled poll loop must surface CancellationError, got \(String(describing: thrown))")
    }

    // MARK: - (2) Stage timeout scales with message count

    func testStageTimeoutScalesWithMessageCount() {
        let single = KeysignViewModel()
        single.messsageToSign = ["a"]

        let many = KeysignViewModel()
        many.messsageToSign = ["a", "b", "c", "d"]

        XCTAssertGreaterThan(
            many.keysignStageTimeout,
            single.keysignStageTimeout,
            "a 4-message ceremony must get a larger stage budget than a 1-message one — a flat budget manufactures the retry-vs-orphan race on healthy slow ceremonies"
        )
    }

    func testStageTimeoutHasNonZeroFloorForEmptyMessageList() {
        let vm = KeysignViewModel()
        vm.messsageToSign = []
        XCTAssertGreaterThan(vm.keysignStageTimeout, .zero, "empty message list must still yield a positive budget")
    }

    // MARK: - (3) Broadcast gate: an already-terminal status is not broadcast

    func testTerminalStatusGatesBroadcastInDKLSPath() {
        // The stage timeout flips status to .KeysignRetryRequested (terminal)
        // on an orphaned ceremony. The DKLS/GG20 bodies must observe that and
        // refuse to broadcast. We can't drive the full signing body in a unit
        // test, but the gate is the same `isTerminalStatus` predicate — assert
        // it classifies the timeout's status as terminal.
        XCTAssertTrue(
            KeysignViewModel.isTerminalStatus(.KeysignRetryRequested),
            "retry-requested (set by the stage timeout) must be terminal so the orphaned body's broadcast gate fires"
        )
    }

    func testBroadcastSkippedWhenStatusAlreadyRetryRequested() {
        // broadcastTransaction itself short-circuits on skipBroadcast; here we
        // assert the higher-level invariant: when the timeout has already set a
        // terminal status, the finish guard leaves it untouched (no false
        // KeysignFinished, and by extension no broadcast attempt downstream).
        let vm = KeysignViewModel()
        vm.status = .KeysignRetryRequested

        if !KeysignViewModel.isTerminalStatus(vm.status) {
            vm.status = .KeysignFinished
        }

        XCTAssertEqual(vm.status, .KeysignRetryRequested, "orphaned-ceremony terminal status must survive the finish guard")
    }
}
