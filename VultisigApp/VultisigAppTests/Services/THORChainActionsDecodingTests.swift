//
//  THORChainActionsDecodingTests.swift
//  VultisigAppTests
//
//  Midgard quotes its numerics. `metadata.failed.code` was typed `Int`, so a
//  live `"code": "99"` threw `typeMismatch` — and a throw anywhere aborts the
//  decode of the WHOLE actions page, which stopped THORChain status polling for
//  every transaction in it, not just the failed one.
//
//  The fixtures below are captured verbatim from mainnet Midgard.
//

import XCTest
@testable import VultisigApp

final class THORChainActionsDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> THORChainActionsResponse {
        try JSONDecoder().decode(THORChainActionsResponse.self, from: Data(json.utf8))
    }

    // MARK: - The wire form Midgard actually serves

    /// ⚠️ The regression. `"code": "99"`, verbatim, from a rejected limit-order
    /// swap. Against `code: Int?` this throws
    /// `typeMismatch … actions[0].metadata.failed.code`.
    func testAQuotedFailureCodeDecodes() throws {
        let response = try decode(Self.failedAction(code: "\"99\""))

        let failed = try XCTUnwrap(response.actions.first?.metadata?.failed)
        XCTAssertEqual(failed.code, "99")
        XCTAssertEqual(
            failed.reason,
            "failed to execute message; message index: 0: could not find matching limit swap: internal error"
        )
        XCTAssertEqual(failed.memo, "m=<:370939666THOR.RUNE:167889485ETH.USDC-06EB48:0")
    }

    /// The same convention on the other metadata block that carries a code.
    func testAQuotedRefundCodeDecodes() throws {
        let response = try decode(Self.refundAction(code: "\"99\""))

        let refund = try XCTUnwrap(response.actions.first?.metadata?.refund)
        XCTAssertEqual(refund.code, "99")
        XCTAssertEqual(refund.reason, "emit asset 145824 less than price limit 149000")
    }

    /// ⚠️ The blast radius, and the reason this was fatal rather than cosmetic:
    /// one undecodable action takes the entire page with it, so a single failed
    /// swap anywhere in the response stopped polling for everything in it.
    func testAFailedActionDoesNotTakeTheRestOfThePageWithIt() throws {
        let response = try decode(Self.pageWithASuccessfulSwapAndAFailedAction)

        XCTAssertEqual(response.actions.count, 2)
        XCTAssertEqual(response.actions.first?.type, "swap")
        XCTAssertEqual(response.actions.last?.metadata?.failed?.code, "99")
    }

    // MARK: - Tolerating the schema's own account of itself

    /// Midgard's schema calls these integers even though it serialises strings.
    /// Accept both, so the same mismatch cannot cost a whole page again.
    func testABareNumericCodeAlsoDecodes() throws {
        let refund = try decode(Self.refundAction(code: "99")).actions.first?.metadata?.refund
        XCTAssertEqual(refund?.code, "99")

        let failed = try decode(Self.failedAction(code: "99")).actions.first?.metadata?.failed
        XCTAssertEqual(failed?.code, "99")
    }

    func testAnAbsentOrNullCodeIsNil() throws {
        let absent = try decode(Self.refundAction(code: nil)).actions.first?.metadata?.refund
        XCTAssertNotNil(absent)
        XCTAssertNil(absent?.code)

        let null = try decode(Self.refundAction(code: "null")).actions.first?.metadata?.refund
        XCTAssertNotNil(null)
        XCTAssertNil(null?.code)
    }

    func testANonNumericCodeStillFails() {
        XCTAssertThrowsError(try decode(Self.refundAction(code: "{}")))
    }

    // MARK: - Call site

    /// The code is display-only, and this is the only place it is displayed.
    func testTheFailureCodeIsRenderedInTheStatusReason() async throws {
        let provider = THORChainTransactionStatusProvider(
            httpClient: StubActionsHTTPClient(Self.refundAction(code: "\"99\"", status: "refund"))
        )

        let result = try await provider.checkStatus(
            query: TransactionStatusQuery(txHash: "ABC123", chain: .thorChain)
        )

        guard case let .failed(reason) = result.status else {
            return XCTFail("Expected a refunded action to map to .failed, got \(result.status)")
        }
        XCTAssertTrue(reason.contains("Code: 99"), reason)
    }

    // MARK: - Fixtures

    /// The `metadata` block is verbatim from the live response for a rejected
    /// limit-order swap; the envelope around it is a Midgard action of that shape.
    private static func failedAction(code: String) -> String {
        """
        {"actions":[{"pools":[],"type":"failed","status":"success",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
          "out":[],"date":"1784733471384558083","height":"27113740",
          "metadata":{"failed":{
            "code":\(code),
            "memo":"m=<:370939666THOR.RUNE:167889485ETH.USDC-06EB48:0",
            "reason":"failed to execute message; message index: 0: could not find matching limit swap: internal error"
          }}}],"count":"1"}
        """
    }

    private static func refundAction(code: String?, status: String = "success") -> String {
        let codeField = code.map { "\"code\":\($0)," } ?? ""
        return """
        {"actions":[{"pools":[],"type":"refund","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"300000000","asset":"THOR.RUNE"}]}],
          "out":[],"date":"1784733471384558083","height":"27113740",
          "metadata":{"refund":{\(codeField)
            "reason":"emit asset 145824 less than price limit 149000",
            "networkFees":[{"amount":"2000000","asset":"THOR.RUNE"}]
          }}}],"count":"1"}
        """
    }

    private static let pageWithASuccessfulSwapAndAFailedAction = """
    {"actions":[
      {"pools":["ETH.ETH"],"type":"swap","status":"success",
       "in":[{"txID":"AAA111","address":"thor1from","coins":[]}],
       "out":[],"date":"1784733440727466355","height":"27113735"},
      {"pools":[],"type":"failed","status":"success",
       "in":[{"txID":"BBB222","address":"thor1from","coins":[]}],
       "out":[],"date":"1784733471384558083","height":"27113740",
       "metadata":{"failed":{"code":"99","reason":"could not find matching limit swap"}}}
    ],"count":"2"}
    """
}

// MARK: - Fakes

private struct StubActionsHTTPClient: HTTPClientProtocol {
    private let json: String

    init(_ json: String) {
        self.json = json
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }
}
