//
//  SuiServiceGetAllCoinsTests.swift
//  VultisigApp
//
//  Pins the fail-loud pagination contract of `SuiService.getAllCoins`: when a
//  page of the coin-object connection cannot be decoded mid-pagination, the call
//  must THROW rather than return the coins decoded so far. A truncated coin set
//  is worse than no set — downstream coin-object selection in `SuiHelper` would
//  silently miss the SUI gas object or the token's objects and build an invalid
//  transaction. The happy path must still follow `hasNextPage`/`endCursor` to
//  completion.
//
//  These assertions are deliberately unchanged from the JSON-RPC era: only the
//  fixture shapes moved to GraphQL, so a passing run says the transport swap
//  preserved the contract rather than that the contract was rewritten to fit.
//

@testable import VultisigApp
import XCTest

final class SuiServiceGetAllCoinsTests: XCTestCase {

    private static let stubHost = "sui-getallcoins-stub.local"

    override func setUp() {
        super.setUp()
        StubRPCProtocol.pages = []
        StubRPCProtocol.requestCount = 0
        URLProtocol.registerClass(StubRPCProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubRPCProtocol.self)
        StubRPCProtocol.pages = []
        super.tearDown()
    }

    // MARK: - Happy path: full pagination

    func testGetAllCoinsFollowsPaginationToCompletion() async throws {
        StubRPCProtocol.pages = [
            Self.page(coins: [Self.coinJSON(id: "0x1")], nextCursor: "cursor-1", hasNextPage: true),
            Self.page(coins: [Self.coinJSON(id: "0x2")], nextCursor: nil, hasNextPage: false)
        ]

        let service = SuiService(resolver: StubResolver(host: Self.stubHost))
        let coins = try await service.getAllCoins(coin: Self.makeCoin())

        XCTAssertEqual(coins.count, 2, "Both pages must be merged into the result")
        XCTAssertEqual(coins.map { $0["objectID"] }, ["0x1", "0x2"])
        XCTAssertEqual(StubRPCProtocol.requestCount, 2, "Pagination must stop once hasNextPage is false")
    }

    // MARK: - Fail loud on a mid-pagination decode failure

    func testGetAllCoinsThrowsWhenLaterPageFailsToDecode() async {
        // Page 1 decodes and advertises a next page; page 2 is malformed
        // (no `result.data`). A truncated set must never be returned.
        StubRPCProtocol.pages = [
            Self.page(coins: [Self.coinJSON(id: "0x1")], nextCursor: "cursor-1", hasNextPage: true),
            Data(#"{"data":{"address":null}}"#.utf8)
        ]

        let service = SuiService(resolver: StubResolver(host: Self.stubHost))

        do {
            let coins = try await service.getAllCoins(coin: Self.makeCoin())
            XCTFail("Expected a decode failure to throw, got \(coins.count) coins")
        } catch {
            // Success: the truncated page-1 result was not handed back.
            XCTAssertEqual(StubRPCProtocol.requestCount, 2, "Both pages must have been fetched before failing")
        }
    }

    func testGetAllCoinsThrowsWhenNextPageHasNoCursor() async {
        StubRPCProtocol.pages = [
            Self.page(coins: [Self.coinJSON(id: "0x1")], nextCursor: nil, hasNextPage: true)
        ]

        let service = SuiService(resolver: StubResolver(host: Self.stubHost))

        do {
            _ = try await service.getAllCoins(coin: Self.makeCoin())
            XCTFail("Expected an invalid pagination cursor to throw")
        } catch {
            XCTAssertEqual(StubRPCProtocol.requestCount, 1)
        }
    }

    func testGetAllCoinsThrowsWhenCursorRepeats() async {
        StubRPCProtocol.pages = [
            Self.page(coins: [Self.coinJSON(id: "0x1")], nextCursor: "cursor-1", hasNextPage: true),
            Self.page(coins: [Self.coinJSON(id: "0x2")], nextCursor: "cursor-1", hasNextPage: true)
        ]

        let service = SuiService(resolver: StubResolver(host: Self.stubHost))

        do {
            _ = try await service.getAllCoins(coin: Self.makeCoin())
            XCTFail("Expected a repeated pagination cursor to throw")
        } catch {
            XCTAssertEqual(StubRPCProtocol.requestCount, 2)
        }
    }

    func testGetAllCoinsThrowsWhenPaginationExceedsSafetyLimit() async {
        StubRPCProtocol.pages = (0...SuiService.maximumCoinPages).map { index in
            Self.page(
                coins: [Self.coinJSON(id: "0x\(index)")],
                nextCursor: "cursor-\(index)",
                hasNextPage: true
            )
        }

        let service = SuiService(resolver: StubResolver(host: Self.stubHost))

        do {
            _ = try await service.getAllCoins(coin: Self.makeCoin())
            XCTFail("Expected the pagination safety limit to throw")
        } catch {
            XCTAssertEqual(StubRPCProtocol.requestCount, SuiService.maximumCoinPages)
        }
    }

    // MARK: - Fixtures

    private static func makeCoin() -> Coin {
        Coin(asset: TokensStore.Token.suiSUI, address: "0xowner", hexPublicKey: "pub")
    }

    /// One node of the coin-object connection, carrying the WRAPPER type the
    /// node actually returns — `0x2::coin::Coin<T>`, zero-padded — so the
    /// fixtures exercise the unwrap rather than assuming it away.
    private static func coinJSON(id: String) -> String {
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        return """
        {"address":"\(id)","version":1,"digest":"digest-\(id)",\
        "previousTransaction":{"digest":"prev"},\
        "contents":{"type":{"repr":"\(padded)::coin::Coin<\(padded)::sui::SUI>"},\
        "json":{"balance":"100"}}}
        """
    }

    private static func page(coins: [String], nextCursor: String?, hasNextPage: Bool) -> Data {
        let cursorJSON = nextCursor.map { "\"\($0)\"" } ?? "null"
        let body = """
        {"data":{"address":{"objects":{\
        "pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(cursorJSON)},\
        "nodes":[\(coins.joined(separator: ","))]}}}}
        """
        return Data(body.utf8)
    }
}

/// A resolver that points every chain at an in-process stub host so the
/// `URLProtocol` below can intercept the request without hitting the network.
private struct StubResolver: RPCEndpointResolving {
    let host: String
    func url(for _: Chain) -> String? { "https://\(host)/rpc" }
}

/// Serves canned JSON-RPC responses in order. Each call to `getAllCoins` issues
/// one POST per page; we pop the next queued page off `pages`.
private final class StubRPCProtocol: URLProtocol {
    static var pages: [Data] = []
    static var requestCount = 0

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "sui-getallcoins-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let index = Self.requestCount
        Self.requestCount += 1

        let body = index < Self.pages.count ? Self.pages[index] : Data("{}".utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
