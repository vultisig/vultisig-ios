//
//  SolanaServiceCacheTests.swift
//  VultisigAppTests
//
//  The Solana RPC proxy intermittently parks a request for ~60 s before
//  answering it, and a Kamino deposit issues a long chain of reads before
//  anything is signed — so every read that can be served from a previous one is
//  one fewer chance to draw that stall.
//
//  These are the caches on that path. Each one is asserted on the same axes: a
//  repeat read does not reach the network, an expired entry does, the cached
//  value is the value the network gave, and a failure is never remembered as
//  one.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaServiceCacheTests: XCTestCase {

    private static let tableAddress = "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    private static let tableEntries = [
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
        "11111111111111111111111111111111"
    ]

    // MARK: - Address lookup table

    /// A deposit prepares twice — the reserve probe, then the real build — and
    /// both need the same table. One read serves both.
    func testTheSecondReadOfALookupTableIsServedFromCache() async throws {
        let http = CountingSolanaHTTPClient(json: Self.lookupTableJSON())
        let service = makeService(http: http)

        let first = try await service.fetchAddressLookupTable(address: Self.tableAddress)
        let second = try await service.fetchAddressLookupTable(address: Self.tableAddress)

        XCTAssertEqual(first, Self.tableEntries)
        XCTAssertEqual(second, Self.tableEntries)
        XCTAssertEqual(http.callCount(for: "getAddressLookupTable"), 1)
    }

    /// The entry has to expire. A table is append-only, so a stale copy can only
    /// be short of entries — which the Kamino validator refuses rather than
    /// mis-signs — but that refusal lasts as long as the entry does, so a vault
    /// repointed at a new table must not keep failing indefinitely.
    func testAnExpiredLookupTableEntryIsReadAgain() async throws {
        let http = CountingSolanaHTTPClient(json: Self.lookupTableJSON())
        let service = makeService(http: http, addressLookupTableTTL: 0)

        _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)
        _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)

        XCTAssertEqual(http.callCount(for: "getAddressLookupTable"), 2)
    }

    /// Keyed by table address, so one vault's table can never answer for
    /// another's — that would rename every account the transaction addresses.
    func testTheLookupTableCacheIsKeyedByTableAddress() async throws {
        let http = CountingSolanaHTTPClient(json: Self.lookupTableJSON())
        let service = makeService(http: http)

        _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)
        _ = try await service.fetchAddressLookupTable(address: "AnotherTab1e111111111111111111111111111111")

        XCTAssertEqual(http.callCount(for: "getAddressLookupTable"), 2)
    }

    /// And by endpoint. A table address means whatever the cluster answering
    /// for it says it means, the custom-RPC override is resolved per request,
    /// and the shared service outlives a change to it — so switching endpoints
    /// must not be served the previous one's answer.
    func testTheLookupTableCacheIsNamespacedByEndpoint() async throws {
        let http = CountingSolanaHTTPClient(json: Self.lookupTableJSON())
        let resolver = MutableResolver()
        let service = SolanaService(resolver: resolver, httpClient: http)

        _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)
        resolver.override = "https://custom-node.example/rpc"
        _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)

        XCTAssertEqual(http.callCount(for: "getAddressLookupTable"), 2)
    }

    /// A failed read must not be remembered as an answer.
    func testAFailedLookupTableReadIsNotCached() async {
        let http = CountingSolanaHTTPClient(json: #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":null}}"#)
        let service = makeService(http: http)

        for _ in 0..<2 {
            do {
                _ = try await service.fetchAddressLookupTable(address: Self.tableAddress)
                XCTFail("a missing lookup table account must throw")
            } catch let error as SolanaAddressLookupTableError {
                XCTAssertEqual(error, .accountNotFound(Self.tableAddress))
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }

        XCTAssertEqual(http.callCount(for: "getAddressLookupTable"), 2)
    }

    // MARK: - Helpers

    private func makeService(
        http: CountingSolanaHTTPClient,
        addressLookupTableTTL: TimeInterval = SolanaService.defaultAddressLookupTableTTL
    ) -> SolanaService {
        SolanaService(
            resolver: NoOverrideResolver(),
            httpClient: http,
            addressLookupTableTTL: addressLookupTableTTL
        )
    }

    /// A `getAccountInfo` result for a `ProgramState::LookupTable` account: the
    /// 4-byte bincode discriminant, 52 further bytes of `LookupTableMeta`, then
    /// the packed 32-byte addresses.
    private static func lookupTableJSON() -> String {
        var data = [UInt8](repeating: 0, count: SolanaAddressLookupTable.metadataSize)
        data[0] = UInt8(SolanaAddressLookupTable.lookupTableDiscriminant)
        for address in tableEntries {
            guard let decoded = Base58.decodeNoCheck(string: address), decoded.count == 32 else {
                XCTFail("fixture address \(address) is not 32 bytes")
                return ""
            }
            data += [UInt8](decoded)
        }
        let payload = Data(data).base64EncodedString()
        return """
        {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":
        {"owner":"\(SolanaAddressLookupTable.programId)","data":["\(payload)","base64"],
        "lamports":1,"executable":false,"rentEpoch":0}}}
        """
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// A custom-RPC override that can be changed mid-test, the way the real store
/// can change at runtime without the app relaunching.
private final class MutableResolver: RPCEndpointResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var _override: String?

    var override: String? {
        get { lock.withLock { _override } }
        set { lock.withLock { _override = newValue } }
    }

    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { override }
}

/// Serves one canned body and counts how often each RPC method was asked for.
private final class CountingSolanaHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private let json: String
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(json: String) {
        self.json = json
    }

    func callCount(for method: String) -> Int {
        lock.withLock { counts[method] ?? 0 }
    }

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let solana = target as? SolanaAPI else {
            XCTFail("CountingSolanaHTTPClient received a non-Solana target")
            throw HTTPError.invalidResponse
        }
        lock.withLock { counts[Self.name(of: solana.rpcMethod), default: 0] += 1 }

        guard let url = URL(string: "https://test.local"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw HTTPError.invalidResponse
        }
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    /// Only the methods these tests count are named; anything else lands in one
    /// bucket, so an unexpected call is visible rather than silently attributed.
    private static func name(of method: SolanaAPI.Method) -> String {
        switch method {
        case .getAddressLookupTable: return "getAddressLookupTable"
        case .getRecentPrioritizationFees: return "getRecentPrioritizationFees"
        default: return "other"
        }
    }
}
