//
//  SuiTokenDiscoveryTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class SuiTokenDiscoveryTests: XCTestCase {
    private static let owner = "0xowner"
    private static let nativeShort = "0x2::sui::SUI"
    private static let nativeLong = "0x" + String(repeating: "0", count: 63) + "2::sui::SUI"
    private static let goldType = "0x0a2b3c4d5e6f7809000000000000000000000000000000000000000000000001::gold::GOLD"
    private static let silverType = "0x0a2b3c4d5e6f7809000000000000000000000000000000000000000000000002::silver::SILVER"

    func testDiscoveryFollowsAllCoinPagesWithoutOwnedObjectFanout() async throws {
        let client = SuiDiscoveryHTTPClient(
            allCoinPages: [
                .first: Self.coinPage(
                    coins: [
                        Self.coin(type: Self.nativeShort, id: "0xnative"),
                        Self.coin(type: Self.goldType, id: "0xgold")
                    ],
                    nextCursor: "page-2",
                    hasNextPage: true
                ),
                .cursor("page-2"): Self.coinPage(
                    coins: [Self.coin(type: Self.silverType, id: "0xsilver")],
                    nextCursor: nil,
                    hasNextPage: false
                )
            ],
            metadata: [
                Self.goldType: Self.metadata(symbol: "GOLD", decimals: 6),
                Self.silverType: Self.metadata(symbol: "SILVER", decimals: 9)
            ]
        )

        let tokens = try await makeService(client: client).getAllTokensWithMetadata(address: Self.owner)

        XCTAssertEqual(tokens.map(\.ticker), ["GOLD", "SILVER"])
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.filter { $0.method == "getAllCoins" }.map(\.cursor), [nil, "page-2"])
        XCTAssertEqual(requests.filter { $0.method == "getCoinMetadata" }.count, 2)
        XCTAssertFalse(requests.contains { $0.method == "getOwnedObjects" })
        XCTAssertFalse(requests.contains { $0.method == "object" })
    }

    func testDiscoveryDeduplicatesNormalizedTypesAndExcludesNativeSui() async throws {
        let goldShort = Self.shortPackageAddress(Self.goldType)
        let client = SuiDiscoveryHTTPClient(
            allCoinPages: [
                .first: Self.coinPage(
                    coins: [
                        Self.coin(type: Self.nativeShort, id: "0xnative-short"),
                        Self.coin(type: Self.nativeLong, id: "0xnative-long"),
                        Self.coin(type: Self.goldType, id: "0xgold-1"),
                        Self.coin(type: goldShort, id: "0xgold-2"),
                        Self.coin(type: Self.goldType, id: "0xgold-3")
                    ],
                    nextCursor: nil,
                    hasNextPage: false
                )
            ],
            metadata: [Self.goldType: Self.metadata(symbol: "GOLD", decimals: 6)]
        )

        let tokens = try await makeService(client: client).getAllTokensWithMetadata(address: Self.owner)

        let token = try XCTUnwrap(tokens.first)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(token.ticker, "GOLD")
        XCTAssertEqual(token.contractAddress, SuiCoinType.normalize(Self.goldType))

        let requests = await client.recordedRequests()
        let metadataRequests = requests.filter { $0.method == "getCoinMetadata" }
        XCTAssertEqual(metadataRequests.count, 1)
        XCTAssertTrue(SuiCoinType.matches(try XCTUnwrap(metadataRequests.first?.coinType), Self.goldType))
    }

    func testDiscoveryReturnsExactCuratedAssetWithoutMetadataRequest() async throws {
        let curated = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .sui && $0.ticker == "CETUS"
        })
        let reportedType = Self.shortPackageAddress(curated.contractAddress)
        let client = SuiDiscoveryHTTPClient(
            allCoinPages: [
                .first: Self.coinPage(
                    coins: [Self.coin(type: reportedType, id: "0xcetus")],
                    nextCursor: nil,
                    hasNextPage: false
                )
            ],
            metadata: [:]
        )

        let tokens = try await makeService(client: client).getAllTokensWithMetadata(address: Self.owner)

        XCTAssertEqual(tokens, [curated])
        XCTAssertEqual(tokens.first?.priceProviderId, curated.priceProviderId)
        XCTAssertEqual(tokens.first?.logo, curated.logo)
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.map(\.method), ["getAllCoins"])
    }

    private func makeService(client: HTTPClientProtocol) -> SuiService {
        SuiService(resolver: SuiDiscoveryRPCResolver(), httpClient: client)
    }

    /// A coin-object node carrying the WRAPPER type the node returns, so the
    /// discovery tests exercise the unwrap on every fixture rather than being
    /// handed the already-bare type the old JSON-RPC payload provided.
    private static func coin(type: String, id: String) -> String {
        let wrapper = "0x2::coin::Coin<\(type)>"
        return """
        {"address":"\(id)","version":1,"digest":"digest-\(id)",\
        "previousTransaction":{"digest":"previous"},\
        "contents":{"type":{"repr":"\(wrapper)"},"json":{"balance":"10"}}}
        """
    }

    private static func coinPage(coins: [String], nextCursor: String?, hasNextPage: Bool) -> Data {
        let cursor = nextCursor.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            {"data":{"address":{"objects":{\
            "pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(cursor)},\
            "nodes":[\(coins.joined(separator: ","))]}}}}
            """.utf8
        )
    }

    private static func metadata(symbol: String, decimals: Int) -> Data {
        Data(
            """
            {"data":{"coinMetadata":{"decimals":\(decimals),"symbol":"\(symbol)","iconUrl":null}}}
            """.utf8
        )
    }

    private static func shortPackageAddress(_ coinType: String) -> String {
        guard let separator = coinType.range(of: "::") else { return coinType }
        let address = coinType[..<separator.lowerBound]
            .dropFirst(2)
            .drop(while: { $0 == "0" })
        let shortAddress = address.isEmpty ? "0" : String(address)
        return "0x\(shortAddress)\(coinType[separator.lowerBound...])"
    }
}

private struct SuiDiscoveryRPCResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? {
        "https://sui-discovery.test/rpc"
    }
}

private actor SuiDiscoveryHTTPClient: HTTPClientProtocol {
    struct RecordedRequest: Equatable {
        let method: String
        let cursor: String?
        let coinType: String?
    }

    enum Page: Hashable {
        case first
        case cursor(String)
    }

    private let allCoinPages: [Page: Data]
    private let metadata: [String: Data]
    private var requests: [RecordedRequest] = []

    init(allCoinPages: [Page: Data], metadata: [String: Data]) {
        self.allCoinPages = allCoinPages
        self.metadata = metadata
    }

    func recordedRequests() -> [RecordedRequest] {
        requests
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        guard case .requestParameters(let body, _) = target.task,
              let document = body["query"] as? String,
              let variables = body["variables"] as? [String: Any] else {
            throw StubError.invalidRequest
        }

        // The GraphQL operation name stands in for the JSON-RPC method these
        // assertions were originally written against, so the test still says
        // "which call was made, with what" rather than matching on document text.
        let method = Self.operation(in: document)

        let data: Data
        switch method {
        case "getAllCoins":
            guard variables["owner"] as? String == "0xowner" else {
                throw StubError.invalidRequest
            }
            let cursor = variables["cursor"].flatMap { value -> String? in
                guard !(value is NSNull) else { return nil }
                return value as? String
            }
            requests.append(RecordedRequest(method: method, cursor: cursor, coinType: nil))
            let page = cursor.map(Page.cursor) ?? .first
            guard let response = allCoinPages[page] else { throw StubError.unexpectedRequest }
            data = response
        case "getCoinMetadata":
            guard let coinType = variables["coinType"] as? String else { throw StubError.invalidRequest }
            requests.append(RecordedRequest(method: method, cursor: nil, coinType: coinType))
            guard let response = metadata.first(where: {
                SuiCoinType.matches($0.key, coinType)
            })?.value else {
                throw StubError.unexpectedRequest
            }
            data = response
        default:
            requests.append(RecordedRequest(method: method, cursor: nil, coinType: nil))
            throw StubError.unexpectedRequest
        }

        let response = HTTPURLResponse(
            url: target.baseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }

    /// The operation name from `query getAllCoins(...)` / `mutation foo(...)`.
    private static func operation(in document: String) -> String {
        let head = document.prefix(while: { $0 != "(" && $0 != "{" })
        return head.split(separator: " ").dropFirst().first.map(String.init) ?? ""
    }

    private enum StubError: Error {
        case invalidRequest
        case unexpectedRequest
    }
}
