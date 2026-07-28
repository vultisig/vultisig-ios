//
//  BlockchairUtxoPaginationTests.swift
//  VultisigAppTests
//
//  Covers `BlockchairService.fetchBlockchairResponse` paging Blockchair's
//  `utxo` array. Without paging the provider caps the array at the request's
//  `limit` and returns it newest-first, so a large send is planned from a
//  recency-biased slice and can spend an input that is already gone.
//

@testable import VultisigApp
import XCTest

final class BlockchairUtxoPaginationTests: XCTestCase {

    private static let address = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

    private func makeBtcCoinMeta() -> CoinMeta {
        CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "BitcoinLogo",
            decimals: 8,
            priceProviderId: "Bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
    }

    /// Serves `total` synthetic UTXOs, honouring the requested limit/offset.
    /// `reportedCount` is what the address object claims it holds — tests can
    /// make it disagree with reality to exercise the fail-loud paths.
    private func makePagedClient(
        total: Int,
        reportedCount: Int?,
        address: String = BlockchairUtxoPaginationTests.address
    ) -> PagingStubHTTPClient {
        PagingStubHTTPClient { limit, offset in
            let slice = (offset..<min(offset + limit, total)).map { index in
                """
                { "block_id": \(1_000 + index), "transaction_hash": "\(String(format: "%064x", index))", \
                "index": 0, "value": \(10_000 + index) }
                """
            }
            let addressObject = reportedCount.map { "{ \"balance\": 1, \"unspent_output_count\": \($0) }" }
                ?? "{ \"balance\": 1 }"
            return """
            {
              "data": {
                "\(address)": {
                  "address": \(addressObject),
                  "utxo": [\(slice.joined(separator: ","))]
                }
              },
              "context": { "state": 960000 }
            }
            """
        }
    }

    private func fetchUtxos(client: PagingStubHTTPClient, pageSize: Int, maxPages: Int = 20) async throws -> [Blockchair.BlockchairUtxo] {
        let service = BlockchairService(httpClient: client, utxoPageSize: pageSize, maxUtxoPages: maxPages)
        let response = try await service.fetchBlockchairResponse(coin: makeBtcCoinMeta(), address: Self.address)
        return try XCTUnwrap(response.data[Self.address]?.utxo)
    }

    // MARK: - Query parameters

    /// The whole fix rests on the request actually carrying `limit`/`offset`.
    /// Blockchair applies both to `transactions,utxo` in that order, so the
    /// transactions side is pinned to zero and the UTXO side carries the page.
    func testDashboardTargetSendsLimitAndOffsetAsQueryParameters() throws {
        let target = BlockchairAPI.dashboard(address: "addr", chain: "Bitcoin", limit: 1_000, offset: 2_000)

        guard case .requestParameters(let parameters, let encoding) = target.task else {
            return XCTFail("dashboard must send query parameters, got \(target.task)")
        }
        guard case .urlEncoding = encoding else {
            return XCTFail("dashboard parameters must be URL-encoded")
        }
        XCTAssertEqual(parameters["limit"] as? String, "0,1000")
        XCTAssertEqual(parameters["offset"] as? String, "0,2000")
        XCTAssertEqual(target.path, "/blockchair/bitcoin/dashboards/address/addr")
    }

    /// Production defaults: the SDK's 1000-per-page, starting at offset 0.
    func testDefaultPageSizeIsRequested() async throws {
        let client = makePagedClient(total: 3, reportedCount: 3)
        let service = BlockchairService(httpClient: client)

        _ = try await service.fetchBlockchairResponse(coin: makeBtcCoinMeta(), address: Self.address)

        XCTAssertEqual(client.requests, [PagingStubHTTPClient.Request(limit: 1_000, offset: 0)])
        XCTAssertEqual(BlockchairService.defaultUtxoPageSize, 1_000)
        XCTAssertEqual(BlockchairService.defaultMaxUtxoPages, 20)
    }

    // MARK: - Page assembly

    func testSinglePageStopsAfterOneRequest() async throws {
        let client = makePagedClient(total: 4, reportedCount: 4)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 4)
        XCTAssertEqual(client.requests.count, 1)
    }

    /// A total that is an exact multiple of the page size ends on a page the
    /// provider filled completely, which is indistinguishable from "there is
    /// more". The walk pays one empty request to reach the real end of the
    /// list rather than trusting the count to say it is already there.
    func testExactMultipleOfPageSizeWalksPastTheFullFinalPage() async throws {
        let client = makePagedClient(total: 20, reportedCount: 20)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 20)
        XCTAssertEqual(client.requests, [
            .init(limit: 10, offset: 0),
            .init(limit: 10, offset: 10),
            .init(limit: 10, offset: 20)
        ])
        XCTAssertEqual(Set(utxos.compactMap(\.transactionHash)).count, 20, "pages must not be merged with duplicates")
    }

    /// `unspent_output_count` is read once, off the first page, so it can be
    /// stale or under-report what the provider is actually holding. Stopping
    /// on it while a page came back full would hand back exactly the
    /// recency-biased partial set this change exists to prevent.
    func testFullPageDoesNotEndTheWalkWhenTheReportedCountIsAlreadyCovered() async throws {
        let client = makePagedClient(total: 25, reportedCount: 8)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 25, "the walk must reach the end of the list, not stop at the reported count")
        XCTAssertEqual(client.requests.count, 3)
    }

    func testShortFinalPageCompletesTheSet() async throws {
        let client = makePagedClient(total: 23, reportedCount: 23)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 23)
        XCTAssertEqual(client.requests, [
            .init(limit: 10, offset: 0),
            .init(limit: 10, offset: 10),
            .init(limit: 10, offset: 20)
        ])
    }

    /// A provider that omits `unspent_output_count` leaves nothing to verify
    /// completeness against — but a single short page is still provably whole:
    /// we asked for a full page and it had less to give.
    func testAcceptsSingleShortPageWhenNoCountIsReported() async throws {
        let client = makePagedClient(total: 4, reportedCount: nil)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 4)
        XCTAssertEqual(client.requests.count, 1)
    }

    /// Past one page that argument disappears: offset paging skips an entry
    /// whenever one is removed between requests, and the final page is short
    /// either way. With no reported count there is no way to notice, so the
    /// walk fails closed rather than hand back a possibly-gapped set.
    func testThrowsWhenNoCountIsReportedAndTheListSpansPages() async {
        let client = makePagedClient(total: 23, reportedCount: nil)

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10)
            XCTFail("expected unverifiableUtxoSet, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .unverifiableUtxoSet(let retrieved) = error else {
                return XCTFail("expected .unverifiableUtxoSet, got \(error)")
            }
            XCTAssertEqual(retrieved, 10)
        } catch {
            XCTFail("expected BlockchairService.Errors.unverifiableUtxoSet, got \(error)")
        }
    }

    /// The address's UTXO list is newest-first, so a deposit landing between
    /// two page requests slides every entry down and the next offset re-serves
    /// one we already have. A duplicated outpoint in the candidate set would
    /// let the planner spend the same input twice, so pages merge on identity.
    func testMergesPagesOnOutpointIdentity() async throws {
        let duplicate = """
        { "block_id": 900, "transaction_hash": "\(String(repeating: "ab", count: 32))", "index": 1, "value": 5000 }
        """
        let client = PagingStubHTTPClient { _, offset in
            let rows = offset == 0
                ? [duplicate, "{ \"block_id\": 901, \"transaction_hash\": \"\(String(repeating: "cd", count: 32))\", \"index\": 0, \"value\": 6000 }"]
                : [duplicate]
            return """
            {
              "data": {
                "\(Self.address)": {
                  "address": { "balance": 1, "unspent_output_count": 3 },
                  "utxo": [\(rows.joined(separator: ","))]
                }
              }
            }
            """
        }

        // Page 0 returns 2 (a full page), page 1 re-serves one of them and is
        // short, leaving 2 unique against a reported 3 ⇒ fail loud.
        do {
            _ = try await fetchUtxos(client: client, pageSize: 2)
            XCTFail("expected incompleteUtxoSet, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .incompleteUtxoSet(let expected, let retrieved) = error else {
                return XCTFail("expected .incompleteUtxoSet, got \(error)")
            }
            XCTAssertEqual(expected, 3)
            XCTAssertEqual(retrieved, 2, "the duplicated outpoint must be merged, not counted twice")
        }
    }

    // MARK: - Fail-loud paths

    /// Offset paging is only sound over a list that holds still: remove one
    /// entry and everything after it slides up past an offset already walked,
    /// leaving a gap that merging cannot see and that the count check cannot
    /// catch if the count itself under-reports. The reported count moves with
    /// the list, so a change in it is the signal that the offsets went stale.
    func testThrowsWhenTheReportedCountChangesBetweenPages() async {
        let client = PagingStubHTTPClient { limit, offset in
            let rows = (offset..<min(offset + limit, 25)).map { index in
                """
                { "block_id": \(1_000 + index), "transaction_hash": "\(String(format: "%064x", index))", \
                "index": 0, "value": 10000 }
                """
            }
            // The address is spent from between the first and second request.
            let count = offset == 0 ? 25 : 24
            return """
            {
              "data": {
                "\(Self.address)": {
                  "address": { "balance": 1, "unspent_output_count": \(count) },
                  "utxo": [\(rows.joined(separator: ","))]
                }
              }
            }
            """
        }

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10)
            XCTFail("expected utxoSetChangedWhilePaging, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .utxoSetChangedWhilePaging(let was, let became) = error else {
                return XCTFail("expected .utxoSetChangedWhilePaging, got \(error)")
            }
            XCTAssertEqual(was, 25)
            XCTAssertEqual(became, 24)
        } catch {
            XCTFail("expected BlockchairService.Errors.utxoSetChangedWhilePaging, got \(error)")
        }
    }

    /// A page that stops reporting a total is no more verifiable than one
    /// reporting a different total.
    func testThrowsWhenALaterPageStopsReportingTheCount() async {
        let client = PagingStubHTTPClient { limit, offset in
            let rows = (offset..<min(offset + limit, 15)).map { index in
                """
                { "block_id": \(1_000 + index), "transaction_hash": "\(String(format: "%064x", index))", \
                "index": 0, "value": 10000 }
                """
            }
            let addressObject = offset == 0 ? "{ \"balance\": 1, \"unspent_output_count\": 15 }" : "{ \"balance\": 1 }"
            return """
            {
              "data": {
                "\(Self.address)": {
                  "address": \(addressObject),
                  "utxo": [\(rows.joined(separator: ","))]
                }
              }
            }
            """
        }

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10)
            XCTFail("expected utxoSetChangedWhilePaging, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .utxoSetChangedWhilePaging(let was, let became) = error else {
                return XCTFail("expected .utxoSetChangedWhilePaging, got \(error)")
            }
            XCTAssertEqual(was, 15)
            XCTAssertNil(became)
        } catch {
            XCTFail("expected BlockchairService.Errors.utxoSetChangedWhilePaging, got \(error)")
        }
        XCTAssertEqual(client.requests.count, 2)
    }

    /// A steady count across every page is what makes the offsets trustworthy,
    /// so the check must not fire on an ordinary multi-page walk.
    func testStableCountAcrossPagesIsNotTreatedAsAChange() async throws {
        let client = makePagedClient(total: 23, reportedCount: 23)

        let utxos = try await fetchUtxos(client: client, pageSize: 10)

        XCTAssertEqual(utxos.count, 23)
    }

    /// The provider reports more unspent outputs than it ever hands over.
    /// Returning the short set would silently reintroduce the original bug.
    func testThrowsWhenRetrievedCountFallsShortOfReportedCount() async {
        let client = makePagedClient(total: 15, reportedCount: 18)

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10)
            XCTFail("expected incompleteUtxoSet, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .incompleteUtxoSet(let expected, let retrieved) = error else {
                return XCTFail("expected .incompleteUtxoSet, got \(error)")
            }
            XCTAssertEqual(expected, 18)
            XCTAssertEqual(retrieved, 15)
        } catch {
            XCTFail("expected BlockchairService.Errors.incompleteUtxoSet, got \(error)")
        }
    }

    /// An address too large to page through must fail rather than loop: an
    /// unbounded fail-loud walk would hang the send instead of ending it.
    func testThrowsWhenPageCapIsExceeded() async {
        let client = makePagedClient(total: 100, reportedCount: 100)

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10, maxPages: 3)
            XCTFail("expected utxoPageLimitExceeded, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .utxoPageLimitExceeded(let pageLimit, let retrieved) = error else {
                return XCTFail("expected .utxoPageLimitExceeded, got \(error)")
            }
            XCTAssertEqual(pageLimit, 3)
            XCTAssertEqual(retrieved, 30)
        } catch {
            XCTFail("expected BlockchairService.Errors.utxoPageLimitExceeded, got \(error)")
        }
        XCTAssertEqual(client.requests.count, 3, "the walk must stop at the cap, not keep paging")
    }

    /// The cap bounds requests, and the walk only ends on a page the provider
    /// couldn't fill — so the largest set N requests can retrieve is one short
    /// of N full pages. Pin both sides of that boundary.
    func testLargestSetRetrievableWithinThePageCap() async throws {
        let withinCap = makePagedClient(total: 29, reportedCount: 29)
        let utxos = try await fetchUtxos(client: withinCap, pageSize: 10, maxPages: 3)
        XCTAssertEqual(utxos.count, 29)
        XCTAssertEqual(withinCap.requests.count, 3)

        let atCap = makePagedClient(total: 30, reportedCount: 30)
        do {
            _ = try await fetchUtxos(client: atCap, pageSize: 10, maxPages: 3)
            XCTFail("expected utxoPageLimitExceeded, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .utxoPageLimitExceeded = error else {
                return XCTFail("expected .utxoPageLimitExceeded, got \(error)")
            }
        }
    }

    /// A response that doesn't carry the requested address is handed back as
    /// it arrived, so callers keep their own handling of that case (the QBTC
    /// claim flow treats it as a fetch failure, not an empty set).
    func testReturnsResponseUntouchedWhenAddressKeyIsMissing() async throws {
        let client = PagingStubHTTPClient { _, _ in
            """
            { "data": { "someOtherAddress": { "utxo": [] } }, "context": { "state": 960000 } }
            """
        }
        let service = BlockchairService(httpClient: client, utxoPageSize: 10, maxUtxoPages: 20)

        let response = try await service.fetchBlockchairResponse(coin: makeBtcCoinMeta(), address: Self.address)

        XCTAssertNil(response.data[Self.address])
        XCTAssertEqual(response.context?.state, 960_000)
        XCTAssertEqual(client.requests.count, 1)
    }

    /// Losing the address key part-way through is different: an earlier page
    /// already returned UTXOs for it, so the merged response would look
    /// perfectly normal while being short. That has to fail loud.
    func testThrowsWhenAddressKeyDisappearsOnALaterPage() async {
        let client = PagingStubHTTPClient { limit, offset in
            guard offset == 0 else {
                return #"{ "data": { "someOtherAddress": { "utxo": [] } } }"#
            }
            let rows = (0..<limit).map { index in
                """
                { "block_id": \(1_000 + index), "transaction_hash": "\(String(format: "%064x", index))", \
                "index": 0, "value": 10000 }
                """
            }
            return """
            {
              "data": {
                "\(Self.address)": {
                  "address": { "balance": 1, "unspent_output_count": 25 },
                  "utxo": [\(rows.joined(separator: ","))]
                }
              }
            }
            """
        }

        do {
            _ = try await fetchUtxos(client: client, pageSize: 10)
            XCTFail("expected utxoPageMissingAddress, got a result")
        } catch let error as BlockchairService.Errors {
            guard case .utxoPageMissingAddress(let page, let retrieved) = error else {
                return XCTFail("expected .utxoPageMissingAddress, got \(error)")
            }
            XCTAssertEqual(page, 1)
            XCTAssertEqual(retrieved, 10)
        } catch {
            XCTFail("expected BlockchairService.Errors.utxoPageMissingAddress, got \(error)")
        }
    }

    // MARK: - Wire encoding

    /// The parameter dictionary is only half the contract — `HTTPClient`
    /// percent-encodes values before handing them to `URLQueryItem`, so the
    /// comma separating the transactions and UTXO limits has to survive that
    /// round trip or Blockchair silently falls back to its 100-entry default.
    func testEncodedRequestURLCarriesTheCommaSeparatedLimits() async throws {
        CapturingURLProtocol.capturedURL = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: configuration))

        _ = try await client.request(
            BlockchairAPI.dashboard(address: "addr", chain: "Bitcoin", limit: 1_000, offset: 2_000)
        )

        let url = try XCTUnwrap(CapturingURLProtocol.capturedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }

        XCTAssertEqual(url.path, "/blockchair/bitcoin/dashboards/address/addr")
        XCTAssertEqual(query["limit"], "0,1000")
        XCTAssertEqual(query["offset"], "0,2000")
        XCTAssertEqual(url.absoluteString.contains("%2C"), false, "a percent-encoded comma is not what Blockchair parses")
    }

    // MARK: - Cache

    /// `fetchBlockchairData` is what populates the dictionary the keysign
    /// payload factory reads, so the merged set — not just the first page —
    /// has to land there.
    func testFetchBlockchairDataCachesTheMergedSet() async throws {
        let client = makePagedClient(total: 23, reportedCount: 23)
        let service = BlockchairService(httpClient: client, utxoPageSize: 10, maxUtxoPages: 20)
        let coin = makeBtcCoinMeta()

        _ = try await service.fetchBlockchairData(coin: coin, address: Self.address)

        let key = await service.blockchairKey(for: coin, address: Self.address)
        let cached = await service.getByKey(key: key)
        XCTAssertEqual(cached?.utxo?.count, 23)
    }
}

// MARK: - Test double

/// Serves a body per (limit, offset) pair and records every page requested.
private final class PagingStubHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    struct Request: Equatable {
        let limit: Int
        let offset: Int
    }

    private let body: (_ limit: Int, _ offset: Int) -> String
    private let lock = NSLock()
    private var recorded: [Request] = []

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(body: @escaping (_ limit: Int, _ offset: Int) -> String) {
        self.body = body
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? BlockchairAPI,
              case .dashboard(_, _, let limit, let offset) = api else {
            throw HTTPError.invalidURL
        }
        lock.lock()
        recorded.append(Request(limit: limit, offset: offset))
        lock.unlock()

        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://example.test")!
        // swiftlint:disable:next force_unwrapping
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body(limit, offset).utf8), response: response)
    }
}

/// Records the URL `HTTPClient` actually put on the wire and answers with an
/// empty JSON body. Installed on a private `URLSessionConfiguration` rather
/// than the global registry so it can't intercept anything else.
private final class CapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var capturedURL: URL?

    // Required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        Self.capturedURL = request.url
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
