//
//  SuiCustomTokenResolverTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class SuiCustomTokenResolverTests: XCTestCase {
    private static let customCoinType = "0x1234::custom_coin::CUSTOM"
    private static let stubHost = "sui-metadata-stub.local"

    override func setUp() {
        super.setUp()
        SuiMetadataRPCStub.response = Data()
        SuiMetadataRPCStub.requestBody = nil
        URLProtocol.registerClass(SuiMetadataRPCStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SuiMetadataRPCStub.self)
        SuiMetadataRPCStub.response = Data()
        SuiMetadataRPCStub.requestBody = nil
        super.tearDown()
    }

    func testFactoryRoutesSuiStructTagsToMetadataResolver() async throws {
        let metadata = SuiCoinMetadata(decimals: 6, symbol: "CUSTOM", iconUrl: "https://example.com/custom.png")
        let provider = StubSuiMetadataProvider(expectedCoinType: Self.customCoinType, result: metadata)
        let resolver = CustomTokenResolverFactory.make(chain: .sui, suiMetadataProvider: provider)

        XCTAssertTrue(resolver.validate("  \(Self.customCoinType)  "))
        XCTAssertFalse(resolver.validate("0x1234"))

        let fetchedToken = try await resolver.fetchInfo(contract: "  \(Self.customCoinType)  ")
        let token = try XCTUnwrap(fetchedToken)
        XCTAssertEqual(token.chain, .sui)
        XCTAssertEqual(token.ticker, "CUSTOM")
        XCTAssertEqual(token.decimals, 6)
        XCTAssertEqual(token.logo, "https://example.com/custom.png")
        XCTAssertEqual(token.contractAddress, Self.customCoinType)
        XCTAssertFalse(token.isNativeToken)
    }

    func testValidationChecksExpectedCoinTypeShape() {
        let fullAddress = "0x" + String(repeating: "a", count: 64)
        let expectedShapes = [
            "0x2::sui::SUI",
            "2::sui::SUI",
            "\(fullAddress)::module_1::Token_2",
            "0x2::wrapper::Wrapped<vector<0x3::coin::Coin<u8>>>",
            "0x2::_module::_type",
            "0x2::module::Type<unknown>"
        ]
        let invalidShapes = [
            "",
            "   ",
            "0x2",
            "0xzz::sui::SUI",
            "0x2::sui",
            "::sui::SUI",
            "0x2::::SUI",
            "0x2::sui::",
            "0x2 ::sui::SUI",
            "0x\(String(repeating: "a", count: 65))::sui::SUI"
        ]

        let resolver = CustomTokenResolverFactory.make(chain: .sui)
        for coinType in expectedShapes {
            XCTAssertTrue(resolver.validate(coinType), "Expected accepted shape: \(coinType)")
        }
        for coinType in invalidShapes {
            XCTAssertFalse(resolver.validate(coinType), "Expected rejected shape: \(coinType)")
        }
    }

    func testResolverAcceptsZeroDecimalsAndMissingIcon() async throws {
        let metadata = SuiCoinMetadata(decimals: 0, symbol: "WHOLE", iconUrl: nil)
        let provider = StubSuiMetadataProvider(expectedCoinType: Self.customCoinType, result: metadata)
        let resolver = CustomTokenResolverFactory.make(chain: .sui, suiMetadataProvider: provider)

        let fetchedToken = try await resolver.fetchInfo(contract: Self.customCoinType)
        let token = try XCTUnwrap(fetchedToken)
        XCTAssertEqual(token.decimals, 0)
        XCTAssertEqual(token.logo, "")
    }

    func testResolverReturnsNilWhenMetadataIsMissing() async throws {
        let provider = StubSuiMetadataProvider(expectedCoinType: Self.customCoinType, result: nil)
        let resolver = CustomTokenResolverFactory.make(chain: .sui, suiMetadataProvider: provider)

        let token = try await resolver.fetchInfo(contract: Self.customCoinType)

        XCTAssertNil(token)
    }

    func testResolverRejectsNativeSuiToPreventDuplicateToken() async throws {
        let nativeCoinType = SuiConstants.nativeCoinType
        let metadata = SuiCoinMetadata(decimals: 9, symbol: "SUI", iconUrl: nil)
        let provider = StubSuiMetadataProvider(expectedCoinType: nativeCoinType, result: metadata)
        let resolver = CustomTokenResolverFactory.make(chain: .sui, suiMetadataProvider: provider)

        let token = try await resolver.fetchInfo(contract: nativeCoinType)

        XCTAssertNil(token)
    }

    func testResolverReturnsCuratedMetadataWithoutRPCForKnownCoinType() async throws {
        let knownToken = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .sui && $0.ticker == "CETUS"
        })
        let shortCoinType = "0x" + String(knownToken.contractAddress.dropFirst(3))
        let resolver = CustomTokenResolverFactory.make(
            chain: .sui,
            suiMetadataProvider: FailingSuiMetadataProvider()
        )

        let fetchedToken = try await resolver.fetchInfo(contract: shortCoinType)
        let token = try XCTUnwrap(fetchedToken)

        XCTAssertEqual(token, knownToken)
        XCTAssertEqual(token.priceProviderId, knownToken.priceProviderId)
        XCTAssertEqual(token.logo, knownToken.logo)
    }

    func testSuiServiceRequestsAndDecodesCoinMetadata() async throws {
        SuiMetadataRPCStub.response = Data(
            #"{"data":{"coinMetadata":{"decimals":9,"symbol":"CUSTOM","iconUrl":"https://example.com/icon.png"}}}"#.utf8
        )
        let service = SuiService(resolver: SuiMetadataRPCResolver(host: Self.stubHost))

        let fetchedMetadata = try await service.getCoinMetadata(coinType: Self.customCoinType)
        let metadata = try XCTUnwrap(fetchedMetadata)

        XCTAssertEqual(metadata, SuiCoinMetadata(decimals: 9, symbol: "CUSTOM", iconUrl: "https://example.com/icon.png"))
        let request = try XCTUnwrap(SuiMetadataRPCStub.requestBody)
        XCTAssertEqual(
            (request["variables"] as? [String: Any])?["coinType"] as? String,
            Self.customCoinType
        )
        XCTAssertTrue((request["query"] as? String)?.contains("coinMetadata") == true)
    }

    func testSuiServiceReturnsNilForNullMetadata() async throws {
        SuiMetadataRPCStub.response = Data(#"{"data":{"coinMetadata":null}}"#.utf8)
        let service = SuiService(resolver: SuiMetadataRPCResolver(host: Self.stubHost))

        let metadata = try await service.getCoinMetadata(coinType: Self.customCoinType)

        XCTAssertNil(metadata)
    }

    func testSuiServiceThrowsRPCError() async {
        SuiMetadataRPCStub.response = Data(
            #"{"data":null,"errors":[{"message":"Invalid coin type","extensions":{"code":"BAD_USER_INPUT"}}]}"#.utf8
        )
        let service = SuiService(resolver: SuiMetadataRPCResolver(host: Self.stubHost))

        do {
            _ = try await service.getCoinMetadata(coinType: Self.customCoinType)
            XCTFail("Expected the node error to be propagated")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .node(message: "Invalid coin type", code: "BAD_USER_INPUT"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuiServiceReturnsNilWhenMetadataOmitsRequiredFields() async throws {
        // A coin the node cannot describe must be dropped rather than shown at a
        // guessed magnitude or under a placeholder ticker.
        SuiMetadataRPCStub.response = Data(
            #"{"data":{"coinMetadata":{"decimals":null,"symbol":"WAT","iconUrl":null}}}"#.utf8
        )
        let service = SuiService(resolver: SuiMetadataRPCResolver(host: Self.stubHost))

        let metadata = try await service.getCoinMetadata(coinType: Self.customCoinType)

        XCTAssertNil(metadata)
    }
}

private struct StubSuiMetadataProvider: SuiCoinMetadataProviding {
    let expectedCoinType: String
    let result: SuiCoinMetadata?

    func getCoinMetadata(coinType: String) async throws -> SuiCoinMetadata? { // swiftlint:disable:this async_without_await
        guard coinType == expectedCoinType else {
            throw StubSuiMetadataError.unexpectedCoinType(coinType)
        }
        return result
    }
}

private enum StubSuiMetadataError: Error {
    case unexpectedCoinType(String)
    case unexpectedRequest
}

private struct FailingSuiMetadataProvider: SuiCoinMetadataProviding {
    func getCoinMetadata(coinType _: String) async throws -> SuiCoinMetadata? { // swiftlint:disable:this async_without_await
        throw StubSuiMetadataError.unexpectedRequest
    }
}

private struct SuiMetadataRPCResolver: RPCEndpointResolving {
    let host: String

    func url(for _: Chain) -> String? {
        "https://\(host)/rpc"
    }
}

private final class SuiMetadataRPCStub: URLProtocol {
    static var response = Data()
    static var requestBody: [String: Any]?

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "sui-metadata-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        if let body = request.httpBody ?? request.httpBodyStream.flatMap(Self.readData) {
            Self.requestBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readData(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
