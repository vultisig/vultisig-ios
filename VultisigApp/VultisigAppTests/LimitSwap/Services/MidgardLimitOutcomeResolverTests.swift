//
//  MidgardLimitOutcomeResolverTests.swift
//  VultisigAppTests
//
//  This type decides whether a closed limit order filled or expired, and the
//  decision is irreversible. Its one safety property: "the chain says refund"
//  and "Midgard didn't answer" must never be confused.
//
//  That is why it reads `action.status` itself instead of going through
//  `THORChainTransactionStatusProvider`, which folds HTTP 429/5xx into
//  `.failed` — fine for a poller that keeps polling, fatal here, where
//  `.failed` would mean "refunded" and a rate limit would permanently expire a
//  live order.
//

import XCTest
@testable import VultisigApp

@MainActor
final class MidgardLimitOutcomeResolverTests: XCTestCase {

    private func resolve(_ client: StubActionsHTTPClient) async -> LimitOrderOutcome {
        await MidgardLimitOutcomeResolver(httpClient: client)
            .resolveOutcome(inboundTxHash: "ABC123", sourceChain: .thorChain)
    }

    // MARK: - Real answers

    func testASuccessfulActionMeansFilled() async {
        let outcome = await resolve(.body(Self.action(status: "success")))

        XCTAssertEqual(outcome, .filled)
    }

    /// Reported as refunded, NOT expired: an order rejected at placement (halted
    /// pool, bad memo) also refunds, seconds in, with no TTL elapsed. We have no
    /// evidence to tell those apart, so we report the fact and not the story.
    func testARefundedActionMeansRefundedNotExpired() async {
        let outcome = await resolve(.body(Self.action(status: "refund")))

        XCTAssertEqual(outcome, .refunded)
    }

    func testActionStatusIsMatchedCaseInsensitively() async {
        let outcome = await resolve(.body(Self.action(status: "SUCCESS")))

        XCTAssertEqual(outcome, .filled)
    }

    // MARK: - Non-answers must never become outcomes

    func testAPendingActionIsUnresolved() async {
        let outcome = await resolve(.body(Self.action(status: "pending")))

        XCTAssertEqual(outcome, .unresolved)
    }

    /// Not indexed yet — the usual case immediately after an order closes.
    func testNoActionsIsUnresolved() async {
        let outcome = await resolve(.body(#"{"actions":[],"count":"0"}"#))

        XCTAssertEqual(outcome, .unresolved)
    }

    func testAnUnrecognisedActionStatusIsUnresolved() async {
        let outcome = await resolve(.body(Self.action(status: "something_new")))

        XCTAssertEqual(outcome, .unresolved)
    }

    /// The regression this type is shaped around: a rate limit is not a refund.
    /// Routed through `THORChainTransactionStatusProvider` this returned
    /// `.failed`, which would have refunded-out a live resting order permanently.
    func testARateLimitIsUnresolvedNotARefund() async {
        let outcome = await resolve(.failing(statusCode: 429))

        XCTAssertEqual(outcome, .unresolved, "429 is an infrastructure failure, not a refund")
    }

    func testAServerErrorIsUnresolvedNotARefund() async {
        let outcome = await resolve(.failing(statusCode: 503))

        XCTAssertEqual(outcome, .unresolved, "5xx is an infrastructure failure, not a refund")
    }

    func testANetworkFailureIsUnresolvedNotARefund() async {
        let outcome = await resolve(.throwing)

        XCTAssertEqual(outcome, .unresolved)
    }

    func testAnUndecodableBodyIsUnresolvedNotARefund() async {
        let outcome = await resolve(.body("<html>gateway timeout</html>"))

        XCTAssertEqual(outcome, .unresolved)
    }

    // MARK: - Fixtures

    private static func action(status: String) -> String {
        """
        {"actions":[{"pools":["BTC.BTC"],"type":"swap","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[]}],
          "out":[],"date":"1752000000000000000","height":"12345"}],"count":"1"}
        """
    }
}

// MARK: - Fakes

private final class StubActionsHTTPClient: HTTPClientProtocol {
    enum Behaviour {
        case body(String)
        case failing(statusCode: Int)
        case throwing
    }

    private let behaviour: Behaviour

    struct NetworkError: Error {}

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    static func body(_ json: String) -> StubActionsHTTPClient { .init(.body(json)) }
    static func failing(statusCode: Int) -> StubActionsHTTPClient { .init(.failing(statusCode: statusCode)) }
    static var throwing: StubActionsHTTPClient { .init(.throwing) }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let url = URL(string: "https://example.invalid")!
        switch behaviour {
        case let .body(json):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: Data(json.utf8), response: response)
        case let .failing(statusCode):
            // Mirrors what `HTTPClient` does for a non-success code under the
            // default `.successCodes` validation.
            throw HTTPError.statusCode(statusCode, Data())
        case .throwing:
            throw NetworkError()
        }
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw NetworkError()
    }
}
