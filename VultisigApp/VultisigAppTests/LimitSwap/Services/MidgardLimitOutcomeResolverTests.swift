//
//  MidgardLimitOutcomeResolverTests.swift
//  VultisigAppTests
//
//  This type decides why a closed limit order closed, and the decision is
//  irreversible. Two safety properties:
//
//  1. "the chain said X" and "Midgard didn't answer" must never be confused —
//     which is why it reads the actions itself instead of going through
//     `THORChainTransactionStatusProvider`, which folds HTTP 429/5xx into
//     `.failed`. Fine for a poller that keeps polling; fatal here, where
//     `.failed` would mean "closed" and a rate limit would permanently close a
//     live order.
//  2. an unrecognised reason degrades to `.refunded` — the label this tracker
//     gave every closure before the reason was readable at all — never to a
//     guess.
//
//  The fixtures below are the shapes Midgard actually returns, captured against
//  mainnet on 2026-07-22.
//

import XCTest
@testable import VultisigApp

@MainActor
final class MidgardLimitOutcomeResolverTests: XCTestCase {

    private func resolve(_ client: StubActionsHTTPClient) async -> LimitOrderOutcome {
        await MidgardLimitOutcomeResolver(httpClient: client)
            .resolveOutcome(inboundTxHash: "ABC123", sourceChain: .thorChain)
    }

    // MARK: - The chain's own account of the closure

    /// ⚠️ THORChain says so in as many words, and it says so whoever sent the
    /// cancel. Nothing local is consulted — the order Gaston cancelled closed
    /// three blocks after placement, long before the cancel poller could confirm
    /// the transaction, so there was no local record to consult and the closure
    /// read "Refunded".
    func testACancelledOrderIsReadFromTheChainsOwnReason() async {
        let outcome = await resolve(.body(Self.refund(reason: "limit swap cancelled")))

        XCTAssertEqual(outcome, .cancelled)
    }

    func testAnExpiredOrderIsReadFromTheChainsOwnReason() async {
        let outcome = await resolve(.body(Self.refund(reason: "limit swap expired")))

        XCTAssertEqual(outcome, .expired)
    }

    /// A fill is a `swap` action against the same placement hash.
    func testASwapActionMeansFilled() async {
        let outcome = await resolve(.body(Self.swapAction()))

        XCTAssertEqual(outcome, .filled)
    }

    /// ⚠️ `type`, never `status`. Midgard's `status` is only ever `success` or
    /// `pending` and describes the OUTBOUND, so a completed refund carries
    /// `"success"` — which this used to read as a fill. Every closed order, of
    /// every kind, resolved as FILLED.
    func testACompletedRefundIsNotAFillEvenThoughItsStatusSaysSuccess() async {
        let body = Self.refund(reason: "limit swap expired", status: "success")

        let outcome = await resolve(.body(body))

        XCTAssertEqual(outcome, .expired)
        XCTAssertNotEqual(outcome, .filled)
    }

    /// ⚠️ The placement action is not an outcome. A resting order has exactly
    /// this — `type: "limit_swap"`, `status: "success"` — and reading its status
    /// would close a live order as filled.
    func testThePlacementActionAloneIsNotAnOutcome() async {
        let outcome = await resolve(.body(Self.placementAction()))

        XCTAssertEqual(outcome, .unresolved)
    }

    /// A partial fill followed by a closure indexes BOTH. What closed the order
    /// is the refund; the fill split is reported separately, from the queue's
    /// own last observation.
    func testARefundOutranksAFillWhenBothAreIndexed() async {
        let outcome = await resolve(.body(Self.refundAfterPartialFill()))

        XCTAssertEqual(outcome, .expired)
    }

    func testTheReasonIsMatchedCaseAndWhitespaceInsensitively() {
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: "LIMIT SWAP CANCELLED"), .cancelled)
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: "  limit swap expired\n"), .expired)
    }

    // MARK: - Failing closed on anything we don't recognise

    /// ⚠️ A reworded reason must cost a LABEL, never produce a wrong one.
    /// `.refunded` is exactly what this tracker reported before any reason was
    /// readable, so a future THORNode change degrades into today's behaviour.
    func testAnUnrecognisedReasonFallsBackToRefunded() {
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: "limit swap withdrawn"), .refunded)
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: "emit asset 145824 less than price limit"), .refunded)
    }

    func testAMissingReasonFallsBackToRefunded() async {
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: nil), .refunded)
        XCTAssertEqual(limitOrderCloseOutcome(refundReason: "   "), .refunded)

        let outcome = await resolve(.body(Self.refund(reason: nil)))
        XCTAssertEqual(outcome, .refunded)
    }

    // MARK: - Non-answers must never become outcomes

    /// ⚠️ Indexed is not settled. `refunded` / `cancelled` / `expired` all say
    /// the funds came back, and a `pending` refund is one whose outbound has not
    /// been sent — so it waits a poll rather than saying it early.
    func testARefundWhoseOutboundHasNotSettledIsNotYetAnOutcome() async {
        let outcome = await resolve(
            .body(Self.refund(reason: "limit swap cancelled", status: "pending"))
        )

        XCTAssertEqual(outcome, .unresolved)
    }

    /// ⚠️ And it must not fall back to the FILL while it waits. An order that
    /// partially filled and then closed has both actions indexed; reading the
    /// older one because the newer is still pending would report it filled,
    /// terminally, on the strength of part of the story.
    func testAPendingRefundDoesNotFallBackToAnEarlierPartialFill() async {
        let outcome = await resolve(.body(Self.refundAfterPartialFill(refundStatus: "pending")))

        XCTAssertEqual(outcome, .unresolved)
        XCTAssertNotEqual(outcome, .filled)
    }

    func testAPendingSwapIsNotYetAFill() async {
        let outcome = await resolve(.body(Self.swapAction(status: "pending")))

        XCTAssertEqual(outcome, .unresolved)
    }

    /// Not indexed yet — the usual case immediately after an order closes.
    func testNoActionsIsUnresolved() async {
        let outcome = await resolve(.body(#"{"actions":[],"count":"0"}"#))

        XCTAssertEqual(outcome, .unresolved)
    }

    /// The regression this type is shaped around: a rate limit is not a closure.
    /// Routed through `THORChainTransactionStatusProvider` this returned
    /// `.failed`, which would have closed a live resting order permanently.
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
    //
    // Shapes captured verbatim from mainnet Midgard on 2026-07-22, against the
    // placement hash of an order this app cancelled.

    private static func refund(reason: String?, status: String = "success") -> String {
        let reasonField = reason.map { "\"reason\":\"\($0)\"," } ?? ""
        return """
        {"actions":[{"pools":[],"type":"refund","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"300000000","asset":"THOR.RUNE"}]}],
          "out":[],"date":"1784733471384558083","height":"27113740",
          "metadata":{"refund":{\(reasonField)"memo":"=<:ETH.USDC-06EB48:0xdest:132146694/14400/0"}}}],
          "count":"1"}
        """
    }

    private static func swapAction(status: String = "success") -> String {
        """
        {"actions":[{"pools":["BTC.BTC"],"type":"swap","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[]}],
          "out":[],"date":"1752000000000000000","height":"12345"}],"count":"1"}
        """
    }

    /// What a still-RESTING order looks like: the placement, and nothing else.
    private static func placementAction() -> String {
        """
        {"actions":[{"pools":[],"type":"limit_swap","status":"success",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[]}],
          "out":[],"date":"1784733440727466355","height":"27113735"}],"count":"1"}
        """
    }

    /// Newest first, as Midgard returns them.
    private static func refundAfterPartialFill(refundStatus: String = "success") -> String {
        """
        {"actions":[
          {"pools":[],"type":"refund","status":"\(refundStatus)",
           "in":[{"txID":"ABC123","address":"thor1from","coins":[]}],
           "out":[],"date":"1784733471384558083","height":"27113740",
           "metadata":{"refund":{"reason":"limit swap expired"}}},
          {"pools":["ETH.ETH"],"type":"swap","status":"success",
           "in":[{"txID":"ABC123","address":"thor1from","coins":[]}],
           "out":[],"date":"1784733440727466355","height":"27113735"}
        ],"count":"2"}
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
