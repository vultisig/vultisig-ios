//
//  JoinKeysignDoubleTapGuardTests.swift
//  VultisigAppTests
//
//  Pins the in-flight re-entrancy guard on `JoinKeysignViewModel.joinKeysignCommittee()`.
//  A rapid double-tap on the peer "Join Keysign" button must fire exactly ONE
//  join request: while the first request is in flight the `isJoiningCommittee`
//  flag is set, so a second synchronous call returns at the guard and never
//  issues a second `POST /{session}`. Without the guard a late/failed duplicate
//  response could flip a successful join to a spurious "Signing Error".
//
//  `Utils.sendRequest` hits `URLSession.shared` directly, so we intercept it
//  with a globally registered `URLProtocol` that counts requests and holds the
//  first one open until both taps have been issued.
//

@testable import VultisigApp
import XCTest

@MainActor
final class JoinKeysignDoubleTapGuardTests: XCTestCase {

    private static let stubHost = "join-keysign-double-tap-stub.local"

    override func setUp() {
        super.setUp()
        HoldingStubProtocol.reset()
        URLProtocol.registerClass(HoldingStubProtocol.self)
    }

    override func tearDown() {
        HoldingStubProtocol.release()
        URLProtocol.unregisterClass(HoldingStubProtocol.self)
        HoldingStubProtocol.reset()
        super.tearDown()
    }

    func testDoubleTapIssuesSingleJoinRequest() {
        let viewModel = JoinKeysignViewModel()
        viewModel.serverAddress = "https://\(Self.stubHost)"
        viewModel.sessionID = "session-1"
        viewModel.localPartyID = "party-A"

        // First tap: starts the request, sets the in-flight flag.
        viewModel.joinKeysignCommittee()
        XCTAssertTrue(viewModel.isJoiningCommittee, "First tap must mark the join as in-flight")

        // Second tap arrives while the first request is still held open by the
        // stub. The guard must drop it before any network call is made.
        viewModel.joinKeysignCommittee()

        // The protocol holds the first request open, so by the time both taps
        // have been issued at most one request can have reached the network.
        XCTAssertLessThanOrEqual(
            HoldingStubProtocol.startCount,
            1,
            "A double-tap while in-flight must not start a second join request"
        )

        // Release the held first request so the completion can clear the flag.
        HoldingStubProtocol.release()

        let cleared = expectation(description: "isJoiningCommittee clears on completion")
        Task { @MainActor in
            for _ in 0..<200 where viewModel.isJoiningCommittee {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 5)

        XCTAssertFalse(viewModel.isJoiningCommittee, "Flag must clear once the join request completes")
        XCTAssertEqual(
            HoldingStubProtocol.startCount,
            1,
            "Exactly one join request must have been issued for a double-tap"
        )
    }
}

/// Intercepts the join `POST` and holds it open until `release()` is called, so
/// the test can fire a second tap while the first request is genuinely in flight.
/// Counts every request that begins loading.
private final class HoldingStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _startCount = 0
    private static let gate = DispatchSemaphore(value: 0)
    private static var released = false

    static var startCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _startCount
    }

    static func reset() {
        lock.lock()
        _startCount = 0
        released = false
        lock.unlock()
    }

    static func release() {
        lock.lock()
        let alreadyReleased = released
        released = true
        lock.unlock()
        if !alreadyReleased {
            gate.signal()
        }
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "join-keysign-double-tap-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        Self.lock.lock()
        Self._startCount += 1
        Self.lock.unlock()

        // Block the URLSession worker thread until the test releases the gate,
        // keeping this request "in flight" while the second tap is issued.
        Self.gate.wait()
        Self.gate.signal()

        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
