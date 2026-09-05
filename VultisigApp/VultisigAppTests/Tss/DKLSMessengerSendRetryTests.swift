//
//  DKLSMessengerSendRetryTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import Mediator
import XCTest

final class DKLSMessengerSendRetryTests: XCTestCase {

    private static let encryptionKey = String(repeating: "ab", count: 32)

    private func makeMessenger(http: ScriptedHTTPClient, sleeper: RecordingSleeper) -> DKLSMessenger {
        DKLSMessenger(
            mediatorUrl: "https://relay.invalid",
            sessionID: "session",
            messageID: nil,
            encryptionKeyHex: Self.encryptionKey,
            httpClient: http,
            sleep: sleeper.sleep
        )
    }

    func testTransientFailuresAreRetriedWithBackoffAndTheSameMessage() async throws {
        let http = ScriptedHTTPClient()
        http.enqueue(.failure(HTTPError.timeout))
        http.enqueue(.failure(HTTPError.networkError(URLError(.networkConnectionLost))))
        http.enqueue(.failure(HTTPError.statusCode(503, nil)))
        http.enqueue(.success(()))
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        try await messenger.send("a", to: "b", body: "round-1")

        XCTAssertEqual(http.sentMessages.count, 4)
        XCTAssertEqual(sleeper.durations, [.seconds(1), .seconds(2), .seconds(4)])
        XCTAssertEqual(Set(http.sentMessages.map(\.hash)).count, 1)
        XCTAssertEqual(Set(http.sentMessages.map(\.sequence_no)).count, 1)
        XCTAssertEqual(Set(http.sentMessages.map(\.body)).count, 1)
    }

    func testExhaustedAfterMaxAttempts() async {
        let http = ScriptedHTTPClient()
        for _ in 0..<RelaySendRetryPolicy.maxAttempts {
            http.enqueue(.failure(HTTPError.timeout))
        }
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            try await messenger.send("a", to: "b", body: "round-1")
            XCTFail("expected RelaySendError.exhausted")
        } catch RelaySendError.exhausted(let attempts, let lastError) {
            XCTAssertEqual(attempts, RelaySendRetryPolicy.maxAttempts)
            XCTAssertTrue(lastError is HTTPError)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(http.sentMessages.count, RelaySendRetryPolicy.maxAttempts)
        XCTAssertEqual(sleeper.durations.count, RelaySendRetryPolicy.maxAttempts - 1)
    }

    func testClientErrorIsRejectedWithoutRetry() async {
        let http = ScriptedHTTPClient()
        http.enqueue(.failure(HTTPError.statusCode(400, nil)))
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            try await messenger.send("a", to: "b", body: "round-1")
            XCTFail("expected RelaySendError.rejected")
        } catch RelaySendError.rejected(let status) {
            XCTAssertEqual(status, 400)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(http.sentMessages.count, 1)
        XCTAssertTrue(sleeper.durations.isEmpty)
    }

    func testCancellationIsNotRetried() async {
        let http = ScriptedHTTPClient()
        http.enqueue(.failure(CancellationError()))
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            try await messenger.send("a", to: "b", body: "round-1")
            XCTFail("expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        XCTAssertEqual(http.sentMessages.count, 1)
        XCTAssertTrue(sleeper.durations.isEmpty)
    }

    func testMissingRecipientFailsBeforeAnyRequest() async {
        let http = ScriptedHTTPClient()
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            try await messenger.send("a", to: nil, body: "round-1")
            XCTFail("expected RelaySendError.invalidMessage")
        } catch RelaySendError.invalidMessage {
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(http.requestCount, 0)
        XCTAssertTrue(sleeper.durations.isEmpty)
        XCTAssertEqual(messenger.counter, 1)
    }

    func testFirstAttemptSuccessDoesNotSleepAndAdvancesTheSequence() async throws {
        let http = ScriptedHTTPClient()
        http.enqueue(.success(()))
        http.enqueue(.success(()))
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        try await messenger.send("a", to: "b", body: "round-1")
        try await messenger.send("a", to: "b", body: "round-2")

        XCTAssertEqual(http.sentMessages.map(\.sequence_no), [1, 2])
        XCTAssertTrue(sleeper.durations.isEmpty)
    }

    func testSendUsesTheShortRequestTimeout() async throws {
        let http = ScriptedHTTPClient()
        http.enqueue(.success(()))
        let messenger = makeMessenger(http: http, sleeper: RecordingSleeper())

        try await messenger.send("a", to: "b", body: "round-1")

        XCTAssertEqual(http.timeouts, [RelaySendRetryPolicy.requestTimeout])
    }

    func testExpiredCeremonyDeadlinePreventsTheRequest() async {
        let http = ScriptedHTTPClient()
        let messenger = makeMessenger(http: http, sleeper: RecordingSleeper())

        do {
            try await messenger.send(
                "a",
                to: "b",
                body: "round-1",
                hardDeadline: ContinuousClock.now
            )
            XCTFail("expected the ceremony deadline to stop the send")
        } catch RelaySendError.ceremonyDeadlineExceeded {
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertEqual(http.requestCount, 0)
    }

    func testRequestTimeoutIsClippedToTheCeremonyDeadline() async throws {
        let http = ScriptedHTTPClient()
        http.enqueue(.success(()))
        let messenger = makeMessenger(http: http, sleeper: RecordingSleeper())

        try await messenger.send(
            "a",
            to: "b",
            body: "round-1",
            hardDeadline: ContinuousClock.now.advanced(by: .seconds(4))
        )

        let timeout = try XCTUnwrap(http.timeouts.first)
        XCTAssertGreaterThan(timeout, 0)
        XCTAssertLessThanOrEqual(timeout, 4)
    }

    func testRetryStopsWhenBackoffWouldCrossTheCeremonyDeadline() async {
        let http = ScriptedHTTPClient()
        http.enqueue(.failure(HTTPError.statusCode(503, nil)))
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            try await messenger.send(
                "a",
                to: "b",
                body: "round-1",
                hardDeadline: ContinuousClock.now.advanced(by: .milliseconds(500))
            )
            XCTFail("expected the ceremony deadline to stop retry backoff")
        } catch RelaySendError.ceremonyDeadlineExceeded {
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertEqual(http.requestCount, 1)
        XCTAssertTrue(sleeper.durations.isEmpty)
    }

    func testSetupUploadTimeoutIsClippedToTheCeremonyDeadline() async throws {
        let http = ScriptedHTTPClient()
        http.enqueue(.success(()))
        let messenger = makeMessenger(http: http, sleeper: RecordingSleeper())

        try await messenger.uploadSetupMessage(
            message: "setup",
            nil,
            hardDeadline: ContinuousClock.now.advanced(by: .seconds(4))
        )

        let timeout = try XCTUnwrap(http.timeouts.first)
        XCTAssertGreaterThan(timeout, 0)
        XCTAssertLessThanOrEqual(timeout, 4)
    }

    func testExpiredCeremonyDeadlineStopsSetupDownloadRetries() async {
        let http = ScriptedHTTPClient()
        let sleeper = RecordingSleeper()
        let messenger = makeMessenger(http: http, sleeper: sleeper)

        do {
            _ = try await messenger.downloadSetupMessageWithRetry(
                nil,
                hardDeadline: ContinuousClock.now
            )
            XCTFail("expected the ceremony deadline to stop setup download")
        } catch RelaySendError.ceremonyDeadlineExceeded {
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertEqual(http.requestCount, 0)
        XCTAssertTrue(sleeper.durations.isEmpty)
    }
}

private final class RecordingSleeper: @unchecked Sendable {
    private(set) var durations: [Duration] = []

    var sleep: DKLSMessenger.Sleeper {
        { [self] duration in durations.append(duration) }
    }
}

private final class ScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private var outcomes: [Result<Void, Error>] = []
    private(set) var requestCount = 0
    private(set) var sentMessages: [Message] = []
    private(set) var timeouts: [TimeInterval] = []

    func enqueue(_ outcome: Result<Void, Error>) {
        outcomes.append(outcome)
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        requestCount += 1
        timeouts.append(target.timeoutInterval)
        if let relay = target as? TssRelayAPI, case .sendMessage(_, let message, _, _) = relay.endpoint {
            sentMessages.append(message)
        }
        guard !outcomes.isEmpty else {
            XCTFail("ScriptedHTTPClient exhausted after \(requestCount) requests")
            throw HTTPError.invalidResponse
        }
        try outcomes.removeFirst().get()
        let url = URL(string: "https://relay.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(), response: response)
    }
}
