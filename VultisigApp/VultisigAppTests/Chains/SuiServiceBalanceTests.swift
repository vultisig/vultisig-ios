//
//  SuiServiceBalanceTests.swift
//  VultisigAppTests
//
//  `suix_getAllBalances` returned every coin type and the caller filtered;
//  GraphQL asks for one named type. The protection these tests were written for
//  is unchanged and still the point: the type that goes on the wire must be the
//  coin's EXACT normalized type. Matching by ticker substring cannot tell
//  `0x2::sui::SUI` from `0x…::xsui::XSUI`, and it fails outright for tokens
//  whose on-chain symbol differs from their display ticker (Wormhole-bridged
//  `…::coin::COIN`). Asking the node for the wrong type reports someone else's
//  balance as yours.
//

@testable import VultisigApp
import XCTest

final class SuiServiceBalanceTests: XCTestCase {
    private static let stubHost = "sui-balance-stub.local"
    private static let owner = "0xowner"
    private static let nativeLong = "0x" + String(repeating: "0", count: 63) + "2::sui::SUI"
    private static let bridgedCoin = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"

    override func setUp() {
        super.setUp()
        SuiBalanceRPCStub.reset()
        URLProtocol.registerClass(SuiBalanceRPCStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SuiBalanceRPCStub.self)
        SuiBalanceRPCStub.reset()
        super.tearDown()
    }

    // MARK: - The coin type that goes on the wire

    func testNativeBalanceRequestsTheExactNormalizedCoinType() async throws {
        SuiBalanceRPCStub.configure(response: Self.balanceResponse("123"))

        let balance = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)

        XCTAssertEqual(balance, "123")
        XCTAssertEqual(SuiBalanceRPCStub.lastVariables?["owner"] as? String, Self.owner)
        XCTAssertEqual(
            SuiBalanceRPCStub.lastVariables?["coinType"] as? String,
            SuiConstants.nativeCoinType,
            "A native coin must resolve to the canonical SUI type, never an empty contract address"
        )
    }

    func testTokenBalanceRequestsTheContractWhenTickerDiffersFromStructName() async throws {
        SuiBalanceRPCStub.configure(response: Self.balanceResponse("456"))
        let coin = CoinMeta(
            chain: .sui,
            ticker: "USDC",
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: Self.bridgedCoin,
            isNativeToken: false
        )

        let balance = try await makeService().getBalance(coin: coin, address: Self.owner)

        XCTAssertEqual(balance, "456")
        XCTAssertEqual(
            SuiBalanceRPCStub.lastVariables?["coinType"] as? String,
            Self.bridgedCoin,
            "The exact contract must be asked for — the ticker says USDC but the struct says COIN"
        )
    }

    func testLongFormNativeTypeIsAcceptedFromTheNode() async throws {
        // The node spells the address zero-padded; the value is returned as-is
        // because the app only ever asked about one type.
        SuiBalanceRPCStub.configure(response: Self.balanceResponse("789"))

        let balance = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)

        XCTAssertEqual(balance, "789")
        XCTAssertTrue(SuiCoinType.matches(Self.nativeLong, SuiConstants.nativeCoinType))
    }

    // MARK: - Absence vs failure

    func testNeverHeldCoinTypeReturnsZero() async throws {
        // An address that has never held the type resolves to null. That is a
        // genuine zero, not an upstream fault.
        SuiBalanceRPCStub.configure(response: Data(#"{"data":{"address":{"balance":null}}}"#.utf8))

        let balance = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)

        XCTAssertEqual(balance, "0")
    }

    func testTransportFailureIsPropagated() async {
        SuiBalanceRPCStub.configure(error: URLError(.timedOut))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected the transport error to be propagated")
        } catch HTTPError.timeout {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNodeRefusalIsPropagatedRatherThanShownAsZero() async {
        // GraphQL answers HTTP 200 even when it refuses, so a populated `errors`
        // array is the only failure signal. Reading it as an empty balance would
        // show someone an empty wallet during an indexer outage.
        SuiBalanceRPCStub.configure(response: Data(
            #"{"data":null,"errors":[{"message":"node unavailable","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#.utf8
        ))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected the node error to be propagated")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .node(message: "node unavailable", code: "INTERNAL_SERVER_ERROR"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedEnvelopeIsPropagated() async {
        SuiBalanceRPCStub.configure(response: Data(#"{}"#.utf8))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected a malformed response error")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnparseableBalanceThrowsRatherThanReadingAsZero() async {
        // A present-but-unparseable amount is a node contract violation, not an
        // empty wallet.
        SuiBalanceRPCStub.configure(response: Self.balanceResponse("not-a-number"))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected an unparseable balance to throw")
        } catch SuiBalanceError.unparseableBalance(let raw) {
            XCTAssertEqual(raw, "not-a-number")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Custom RPC still speaking JSON-RPC

    func testJSONRPCEndpointIsReportedAsSuchRatherThanAsMalformed() async {
        // A custom Sui RPC saved before the migration answers a GraphQL POST
        // with a JSON-RPC envelope. The user has to be able to tell that apart
        // from "the node is broken", because the fix is theirs to make.
        SuiBalanceRPCStub.configure(response: Data(
            #"{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}"#.utf8
        ))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected the legacy-endpoint error")
        } catch let error as SuiRPCError {
            guard case .legacyJSONRPCEndpoint(let host) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(host.contains(Self.stubHost))
            XCTAssertTrue(error.localizedDescription.contains("JSON-RPC"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService() -> SuiService {
        SuiService(resolver: SuiBalanceRPCResolver(host: Self.stubHost))
    }

    private static func balanceResponse(_ totalBalance: String) -> Data {
        Data(#"{"data":{"address":{"balance":{"totalBalance":"\#(totalBalance)"}}}}"#.utf8)
    }
}

private struct SuiBalanceRPCResolver: RPCEndpointResolving {
    let host: String

    func url(for _: Chain) -> String? {
        "https://\(host)/rpc"
    }
}

private final class SuiBalanceRPCStub: URLProtocol {
    private enum Outcome {
        case response(Data)
        case error(Error)
    }

    private static let lock = NSLock()
    private static var outcome = Outcome.response(Data("{}".utf8))
    private static var variables: [String: Any]?

    /// The `variables` object of the last GraphQL request, so a test can assert
    /// which coin type actually went on the wire.
    static var lastVariables: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return variables
    }

    static func configure(response: Data) {
        lock.lock()
        defer { lock.unlock() }
        outcome = .response(response)
    }

    static func configure(error: Error) {
        lock.lock()
        defer { lock.unlock() }
        outcome = .error(error)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        outcome = .response(Data("{}".utf8))
        variables = nil
    }

    private static func record(_ request: URLRequest) {
        // `URLProtocol` strips the body from `request`; it survives on the
        // stream, which is what `httpBodyStream` exists for.
        guard let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll) else { return }
        let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        lock.lock()
        variables = (parsed?["variables"] as? [String: Any])
        lock.unlock()
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        guard request.url?.host == "sui-balance-stub.local" else { return false }
        record(request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let current: Outcome
        Self.lock.lock()
        current = Self.outcome
        Self.lock.unlock()

        switch current {
        case .response(let data):
            // Force-unwraps are safe: the URL came from the intercepted request
            // and a 200 response always initializes.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
