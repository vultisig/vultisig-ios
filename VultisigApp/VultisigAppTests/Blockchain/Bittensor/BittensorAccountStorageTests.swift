//
//  BittensorAccountStorageTests.swift
//  VultisigAppTests
//
//  A failed balance lookup must remain unknown so destination validation
//  cannot mistake malformed RPC data for a confirmed empty account.

import BigInt
import XCTest
@testable import VultisigApp

final class BittensorAccountStorageTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BittensorStorageRPCStub.responseData = Data()
        BittensorStorageRPCStub.requestCount = 0
        URLProtocol.registerClass(BittensorStorageRPCStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(BittensorStorageRPCStub.self)
        BittensorStorageRPCStub.responseData = Data()
        super.tearDown()
    }

    // MARK: - interpretAccountStorage (pure — no network)

    func testNilResultIsConfirmedZero() {
        // A nil `state_getStorage` response means the storage key doesn't
        // exist — the account has no ledger entry, which IS a confirmed
        // zero balance, not an unknown read.
        XCTAssertEqual(BittensorHelper.interpretAccountStorage(nil), .confirmed(.zero))
    }

    func testEmptyStringResultIsUnknownNotZero() {
        // An actual empty STRING is NOT Substrate's "no value" sentinel —
        // that's JSON null, mapped to `nil` above. A well-formed node never
        // returns an empty string for this call, so treat it as unknown.
        XCTAssertEqual(BittensorHelper.interpretAccountStorage(""), .unknown)
    }

    func testTruncatedHexIsUnknownNotZero() {
        // Non-empty but shorter than the AccountInfo layout requires
        // (64 hex chars covering nonce/consumers/providers/sufficients/free)
        // is a malformed or truncated read, not a confirmed value.
        XCTAssertEqual(BittensorHelper.interpretAccountStorage("0x1234"), .unknown)
        XCTAssertEqual(BittensorHelper.interpretAccountStorage("1234"), .unknown)
    }

    func testMalformedFreeBalanceHexIsUnknownNotZero() {
        // 64+ hex chars, so the length guard passes, but the free-balance
        // field itself contains non-hex characters.
        // That must not fall back to a confirmed zero.
        let padding = String(repeating: "0", count: 32)
        let malformedFree = "zzzzzzzz" + String(repeating: "0", count: 24)
        let hex = padding + malformedFree

        XCTAssertEqual(BittensorHelper.interpretAccountStorage(hex), .unknown)
    }

    func testMalformedStorageOutsideTheBalanceFieldIsUnknown() {
        let zeroAccount = String(repeating: "0", count: 160)
        XCTAssertEqual(BittensorHelper.interpretAccountStorage("z" + zeroAccount.dropFirst()), .unknown)
        XCTAssertEqual(BittensorHelper.interpretAccountStorage(zeroAccount + "0"), .unknown)
    }

    func testMalformedRPCResultsRemainUnknownThroughTheRealService() async throws {
        let malformed: [Any] = [42, false, ["balance": 0], [], "", "0x1234", "0x" + String(repeating: "z", count: 160)]
        for (index, result) in malformed.enumerated() {
            try setRPCResult(result)
            let balance = try await makeService().getBalanceIfKnown(address: Self.address)
            XCTAssertNil(balance, "Malformed RPC result must not become a confirmed zero: \(result)")
            XCTAssertEqual(BittensorStorageRPCStub.requestCount, index + 1, "The real RPC decoder must be exercised")
        }
    }

    func testJSONNullIsConfirmedZeroThroughTheRealService() async throws {
        try setRPCResult(NSNull())
        let balance = try await makeService().getBalanceIfKnown(address: Self.address)
        XCTAssertEqual(balance, .zero)
        XCTAssertEqual(BittensorStorageRPCStub.requestCount, 1)
    }

    func testEncodedZeroIsConfirmedZeroThroughTheRealService() async throws {
        try setRPCResult(Self.accountStorage(freeLE: String(repeating: "0", count: 32)))
        let balance = try await makeService().getBalanceIfKnown(address: Self.address)
        XCTAssertEqual(balance, .zero)
        XCTAssertEqual(BittensorStorageRPCStub.requestCount, 1)
    }

    func testUnknownRPCReadDoesNotCacheAZeroBalance() async throws {
        let service = makeService()
        try setRPCResult(["unexpected": true])
        let unknown = try await service.getBalanceIfKnown(address: Self.address)
        XCTAssertNil(unknown)

        try setRPCResult(Self.accountStorage(freeLE: "00ca9a3b" + String(repeating: "0", count: 24)))
        let funded = try await service.getBalanceIfKnown(address: Self.address)
        XCTAssertEqual(funded, BigInt(1_000_000_000))
        XCTAssertEqual(BittensorStorageRPCStub.requestCount, 2)
    }

    func testAbsentAccountCanBeReadAgainAfterFunding() async throws {
        let service = makeService()
        try setRPCResult(NSNull())
        let empty = try await service.getBalanceIfKnown(address: Self.address)
        XCTAssertEqual(empty, .zero)

        try setRPCResult(Self.accountStorage(freeLE: "00ca9a3b" + String(repeating: "0", count: 24)))
        let funded = try await service.getBalanceIfKnown(address: Self.address)
        XCTAssertEqual(funded, BigInt(1_000_000_000))
        XCTAssertEqual(BittensorStorageRPCStub.requestCount, 2)
    }

    private static let address = "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuXG"

    private func makeService() -> BittensorService {
        XCTAssertNotNil(BittensorHelper.ss58Decode(Self.address), "Fixture must reach RPC rather than fail address decoding")
        return BittensorService("https://bittensor-storage-stub.local/rpc", resolver: BittensorStorageRPCResolver())
    }

    private func setRPCResult(_ result: Any) throws {
        BittensorStorageRPCStub.responseData = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": result])
    }

    private static func accountStorage(freeLE: String) -> String {
        "0x" + String(repeating: "0", count: 32) + freeLE + String(repeating: "0", count: 96)
    }

    func testWellFormedHexParsesTheFreeBalanceField() {
        // nonce(4) + consumers(4) + providers(4) + sufficients(4) = 16 bytes / 32 hex
        // chars of padding, then free balance (u128 LE) at hex chars 32-63.
        // 1_000_000_000 rao = 0x3B9ACA00, little-endian bytes 00 CA 9A 3B
        // padded to 16 bytes.
        let padding = String(repeating: "0", count: 32)
        let freeLE = "00ca9a3b" + String(repeating: "0", count: 24)
        let hex = "0x" + padding + freeLE

        XCTAssertEqual(BittensorHelper.interpretAccountStorage(hex), .confirmed(BigInt(1_000_000_000)))
    }

    func testWellFormedHexWithoutPrefixParsesTheSame() {
        let padding = String(repeating: "0", count: 32)
        let freeLE = "00ca9a3b" + String(repeating: "0", count: 24)
        let hex = padding + freeLE

        XCTAssertEqual(BittensorHelper.interpretAccountStorage(hex), .confirmed(BigInt(1_000_000_000)))
    }

    // MARK: - Undecodable address (real service, no network reached)

    /// `ss58Decode` fails synchronously before `fetchBalanceRead` ever builds
    /// a storage key or calls the RPC layer, so this exercises the real
    /// `BittensorService` — not a stub — with no network access.
    func testUndecodableAddressIsUnknownNotZero() async throws {
        let unknown = try await BittensorService.shared.getBalanceIfKnown(address: "!!!not-a-valid-ss58-address!!!")
        XCTAssertNil(unknown)
    }

    /// `getBalance` (the wallet-balance-display API, unchanged by this fix)
    /// still collapses the same undecodable address to "0" — confirming the
    /// fix is additive and doesn't alter `BalanceService`'s existing
    /// behavior.
    func testGetBalanceStillReturnsZeroStringForUndecodableAddress() async throws {
        let balance = try await BittensorService.shared.getBalance(address: "!!!not-a-valid-ss58-address!!!")
        XCTAssertEqual(balance, "0")
    }
}

private struct BittensorStorageRPCResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { "https://bittensor-storage-stub.local/rpc" }
}

private final class BittensorStorageRPCStub: URLProtocol {
    static var responseData = Data()
    static var requestCount = 0

    // Required URLProtocol overrides.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bittensor-storage-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestCount += 1
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
