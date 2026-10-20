//
//  NearRPCErrorTests.swift
//  VultisigAppTests
//
//  NEAR error typing for endpoints that drop nearcore's structured error name.
//  The name-less bodies are verbatim captures from api.vultisig.com/near/ and
//  the structured ones from rpc.mainnet.near.org (2026-10-19).
//

@testable import VultisigApp
import XCTest

private struct NoRPCOverride: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

private final class CannedNearNode: HTTPClientProtocol, @unchecked Sendable {
    private let body: String

    init(body: String) {
        self.body = body
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let response = HTTPURLResponse(url: target.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    // swiftlint:disable:next async_without_await
    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
}

final class NearRPCErrorTests: XCTestCase {

    private static let account = "feab75c08be2732f1976726b25190ee2fec15ecc6e895532243fb8f3fd54e7db"
    private static let txHash = "3t5WgoCJTmf5aZsZoFF8fZusBN7yfR2uKvpMDKh7xd5o"
    private static let sender = "eaacfd92874d932c636aeceb051566762b9bf8b8791f267eacd96ead4832a4f1"

    private static let namelessUnknownAccount = #"{"jsonrpc":"2.0","error":{"code":-32000,"message":"Server error","data":"account feab75c08be2732f1976726b25190ee2fec15ecc6e895532243fb8f3fd54e7db does not exist while viewing"},"id":1}"#
    private static let namelessUnknownTransaction = #"{"jsonrpc":"2.0","error":{"code":-32000,"message":"Server error","data":"Transaction 3t5WgoCJTmf5aZsZoFF8fZusBN7yfR2uKvpMDKh7xd5o doesn't exist"},"id":1}"#
    private static let structuredUnknownAccount = #"{"jsonrpc":"2.0","error":{"name":"HANDLER_ERROR","cause":{"info":{"requested_account_id":"feab75c08be2732f1976726b25190ee2fec15ecc6e895532243fb8f3fd54e7db"},"name":"UNKNOWN_ACCOUNT"},"code":-32000,"message":"Server error","data":"account feab75c08be2732f1976726b25190ee2fec15ecc6e895532243fb8f3fd54e7db does not exist while viewing"},"id":1}"#

    func testAnUnknownAccountWithoutAnErrorNameReadsAsUnfunded() async throws {
        let service = NearService(client: CannedNearNode(body: Self.namelessUnknownAccount), resolver: NoRPCOverride())

        let account = try await service.fetchAccount(accountId: Self.account)

        XCTAssertNil(account)
    }

    func testAnUnknownAccountWithAStructuredNameStillReadsAsUnfunded() async throws {
        let service = NearService(client: CannedNearNode(body: Self.structuredUnknownAccount), resolver: NoRPCOverride())

        let account = try await service.fetchAccount(accountId: Self.account)

        XCTAssertNil(account)
    }

    func testAnUnknownTransactionWithoutAnErrorNameIsNotFound() async throws {
        let service = NearService(client: CannedNearNode(body: Self.namelessUnknownTransaction), resolver: NoRPCOverride())
        let provider = NearTransactionStatusProvider(service: service)

        let result = try await provider.checkStatus(query: TransactionStatusQuery(txHash: Self.txHash, chain: .near, senderAccountId: Self.sender))

        XCTAssertEqual(result.status, .notFound)
    }

    func testANamelessErrorWithAnyOtherMessageStaysAnRPCFailure() async {
        let body = #"{"jsonrpc":"2.0","error":{"code":-32000,"message":"Server error","data":"account feab does not exist while viewing, retry later"},"id":1}"#
        let service = NearService(client: CannedNearNode(body: body), resolver: NoRPCOverride())

        do {
            _ = try await service.fetchAccount(accountId: Self.account)
            XCTFail("a failure that is not nearcore's whole not-found message must not read as an unfunded account")
        } catch {
            XCTAssertEqual(
                error as? NearError,
                .rpc(method: "query", name: "UNKNOWN_ERROR", message: "account feab does not exist while viewing, retry later")
            )
        }
    }
}
