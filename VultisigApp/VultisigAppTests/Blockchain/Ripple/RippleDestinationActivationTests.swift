//
//  RippleDestinationActivationTests.swift
//  VultisigAppTests
//
//  Covers the pre-ceremony destination-activation guard: an XRPL Payment that
//  would create the destination account with less than the base reserve fails
//  on-chain (tecNO_DST_INSUF_XRP) after the fee is burned, so the app blocks
//  it before the keysign ceremony starts. Funded destinations pass untouched;
//  a lookup failure fails closed, matching the SDK and Android companions.
//

@testable import VultisigApp
import XCTest
import BigInt

final class RippleDestinationActivationTests: XCTestCase {

    func testFundedDestinationPassesAnyAmount() async throws {
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(fundedAccountJSON(balance: "20000000"))
        let service = makeService(client: client)

        // 1 drop to an existing account is valid — no activation needed.
        try await service.validateDestinationActivation(address: "rFunded", amountDrops: BigInt(1))
    }

    func testUnfundedDestinationBelowBaseReserveThrows() async {
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        do {
            try await service.validateDestinationActivation(address: "rUnfunded", amountDrops: BigInt(999_999))
            XCTFail("an unfunded destination below the base reserve must be blocked")
        } catch let error as RippleSendError {
            guard case .destinationNotActivated(let minimumXRP) = error else {
                return XCTFail("unexpected RippleSendError: \(error)")
            }
            XCTAssertEqual(minimumXRP, "1")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testUnfundedDestinationAtBaseReservePasses() async throws {
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        // Exactly the base reserve activates the account — allowed.
        try await service.validateDestinationActivation(address: "rUnfunded", amountDrops: BigInt(1_000_000))
    }

    func testUnfundedDestinationThresholdTracksLiveBaseReserve() async {
        // A validator vote can raise the base reserve; the guard must follow
        // the live value, not the 1 XRP seed.
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 5_000_000, reserveInc: 1_000_000))
        let service = makeService(client: client)

        do {
            try await service.validateDestinationActivation(address: "rUnfunded", amountDrops: BigInt(2_000_000))
            XCTFail("2 XRP must be blocked when the live base reserve is 5 XRP")
        } catch let error as RippleSendError {
            guard case .destinationNotActivated(let minimumXRP) = error else {
                return XCTFail("unexpected RippleSendError: \(error)")
            }
            XCTAssertEqual(minimumXRP, "5")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testDestinationTransportErrorFailsOpen() async throws {
        // A transport blip (offline, timeout, 429/5xx) is NOT proof the
        // destination is unfunded. Before this guard existed the same send to a
        // funded address proceeded, so a transient lookup failure must fail open
        // rather than start blocking every native XRP send; the on-chain
        // tecNO_DST_INSUF_XRP guard remains the backstop.
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .failure(URLError(.notConnectedToInternet))
        let service = makeService(client: client)

        // Must not throw — the send is allowed.
        try await service.validateDestinationActivation(address: "rUnknown", amountDrops: BigInt(10_000_000))
    }

    func testDestinationRetryableRpcErrorFailsOpen() async throws {
        // A retryable node error (rate-limit / stale pool backend) that survives
        // the bounded same-host retry surfaces as a thrown RippleRetryError — a
        // transport-class failure, not proof the destination is unfunded. Fail
        // open, same as a raw transport error.
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"slowDown","error_message":"You are placing too much load on the server.","status":"error"}}
        """.utf8))
        let service = makeService(client: client)

        try await service.validateDestinationActivation(address: "rUnknown", amountDrops: BigInt(10_000_000))
    }

    func testAmbiguousLookupFailsClosedWithLocalizedError() async {
        // HTTP 200, no account_data, and a non-retryable, non-actNotFound token
        // (a malformed request, a proxy error page): a *successful* response the
        // guard cannot interpret as funded or unfunded, so fail closed — with a
        // localized, non-nil description.
        let client = DestinationScriptedHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"invalidParams","error_message":"Invalid parameters.","status":"error"}}
        """.utf8))
        let service = makeService(client: client)

        do {
            try await service.validateDestinationActivation(address: "rUnknown", amountDrops: BigInt(10_000_000))
            XCTFail("an uninterpretable successful lookup must fail closed")
        } catch let error as RippleSendError {
            guard case .destinationLookupFailed(let code) = error else {
                return XCTFail("unexpected RippleSendError: \(error)")
            }
            XCTAssertEqual(code, "invalidParams")
            XCTAssertNotNil(error.errorDescription, "the fail-closed message must be presentable")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Fixtures

    private func makeService(client: HTTPClientProtocol) -> RippleService {
        // No-op sleeper so the bounded retry on retryable node errors runs
        // without real backoff delays in the test.
        RippleService(resolver: NoOverrideResolver(), httpClient: client, sleep: { _ in })
    }

    private func fundedAccountJSON(balance: String) -> Data {
        Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"\(balance)","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8)
    }

    /// The rippled response for a non-existent account: HTTP 200 with an
    /// `actNotFound` error payload and no `account_data`.
    private func actNotFoundJSON() -> Data {
        Data("""
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """.utf8)
    }

    private func serverStateJSON(reserveBase: Int, reserveInc: Int) -> Data {
        Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":\(reserveBase),"reserve_inc":\(reserveInc)}}}}
        """.utf8)
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted HTTP client keyed on the `RippleAPI` endpoint.
private final class DestinationScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            return try respond(accountInfoResult)
        case .serverState:
            return try respond(serverStateResult)
        case .submit, .tx:
            throw URLError(.unsupportedURL)
        }
    }

    private func respond(_ result: Result<Data, Error>) throws -> HTTPResponse<Data> {
        let data = try result.get()
        guard let url = URL(string: "https://xrplcluster.com"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:enable async_without_await
