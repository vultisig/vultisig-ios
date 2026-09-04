//
//  RelaySendRetryPolicyTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import Mediator
import XCTest

final class RelaySendRetryPolicyTests: XCTestCase {

    func testTransientFaultsAreRetryable() {
        XCTAssertTrue(RelaySendRetryPolicy.isRetryable(HTTPError.timeout))
        XCTAssertTrue(RelaySendRetryPolicy.isRetryable(HTTPError.networkError(URLError(.networkConnectionLost))))
        for code in [500, 502, 503, 599] {
            XCTAssertTrue(RelaySendRetryPolicy.isRetryable(HTTPError.statusCode(code, nil)), "\(code)")
        }
    }

    func testClientErrorsCancellationAndDeterministicFailuresAreNotRetryable() {
        for code in [400, 404, 409, 499] {
            XCTAssertFalse(RelaySendRetryPolicy.isRetryable(HTTPError.statusCode(code, nil)), "\(code)")
        }
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(CancellationError()))
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(HTTPError.networkError(CancellationError())))
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(HTTPError.networkError(URLError(.cancelled))))
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(HTTPError.encodingFailed))
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(HTTPError.decodingFailed(HTTPError.noData)))
        XCTAssertFalse(RelaySendRetryPolicy.isRetryable(RelaySendError.invalidMessage("to is nil")))
    }

    func testBackoffDoublesFromOneSecond() {
        let backoffs = (1..<RelaySendRetryPolicy.maxAttempts).map(RelaySendRetryPolicy.backoff(afterAttempt:))
        XCTAssertEqual(backoffs, [.seconds(1), .seconds(2), .seconds(4)])
    }

    func testWorstCaseBudgetStaysUnderTheCeremonyStall() {
        XCTAssertEqual(RelaySendRetryPolicy.worstCaseBudget, .seconds(39))
        XCTAssertLessThan(
            RelaySendRetryPolicy.worstCaseBudget,
            CeremonyWatchdog.defaultPeerWaitLimit
        )
    }

    func testTheShortTimeoutIsOptInPerRequest() {
        let base = URL(string: "https://relay.example.com")!
        let message = Message(session_id: "s", from: "a", to: ["b"], body: "body", hash: "hash", sequenceNo: 0)
        let send = TssRelayAPI.Endpoint.sendMessage(sessionID: "s", message: message, messageID: nil, addLegacyKeygenHeader: false)

        XCTAssertEqual(RelaySendRetryPolicy.requestTimeout, 8)
        XCTAssertEqual(
            TssRelayAPI(baseURL: base, endpoint: send, timeoutInterval: RelaySendRetryPolicy.requestTimeout).timeoutInterval,
            RelaySendRetryPolicy.requestTimeout
        )

        let defaults: [TssRelayAPI.Endpoint] = [
            send,
            .uploadSetupMessage(sessionID: "s", body: Data(), messageID: nil, additionalHeader: nil),
            .downloadSetupMessage(sessionID: "s", messageID: nil, additionalHeader: nil),
            .pollInboundMessages(sessionID: "s", localPartyID: "p", messageID: nil),
            .deleteMessage(sessionID: "s", localPartyID: "p", hash: "h", messageID: nil),
            .checkKeygenStarted(sessionID: "s")
        ]
        for endpoint in defaults {
            XCTAssertEqual(TssRelayAPI(baseURL: base, endpoint: endpoint).timeoutInterval, 60, "\(endpoint)")
        }
    }

    func testKeygenKickoffCanOptIntoShortTimeoutWhileSessionRequestsDefaultToSixtySeconds() {
        let base = URL(string: "https://relay.example.com")!
        let start = RelayServerAPI.Endpoint.startSession(sessionID: "s", body: Data())

        XCTAssertEqual(
            RelayServerAPI(
                baseURL: base,
                endpoint: start,
                timeoutInterval: RelaySendRetryPolicy.requestTimeout
            ).timeoutInterval,
            RelaySendRetryPolicy.requestTimeout
        )

        let defaults: [RelayServerAPI.Endpoint] = [
            .getParticipants(sessionID: "s"),
            .registerAsParticipant(sessionID: "s", body: Data()),
            start,
            .pollSessionStart(sessionID: "s")
        ]
        for endpoint in defaults {
            XCTAssertEqual(RelayServerAPI(baseURL: base, endpoint: endpoint).timeoutInterval, 60, "\(endpoint)")
        }
    }
}
