//
//  RippleDestinationReserveCheckTests.swift
//  VultisigAppTests
//
//  Covers the non-throwing, send-form reserve check
//  (`RippleService.destinationReserveShortfall`). Unlike the throwing Verify
//  guard (`validateDestinationActivation`), the form check FAILS OPEN — an
//  unverifiable destination returns `.unknown` and shows no inline error, with
//  the Verify guard as the fail-closed backstop. The funded/unfunded verdict
//  is cached per destination address so amount edits don't re-hit the node,
//  and the minimum it reports must match the Verify guard's exactly.
//

@testable import VultisigApp
import XCTest
import BigInt

final class RippleDestinationReserveCheckTests: XCTestCase {

    func testFundedDestinationReturnsSatisfied() async {
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(fundedAccountJSON(balance: "20000000"))
        let service = makeService(client: client)

        // 1 drop to an existing account is valid — no activation minimum.
        let check = await service.destinationReserveShortfall(address: "rFunded", amountDrops: BigInt(1))
        XCTAssertEqual(check, .satisfied)
    }

    func testUnfundedBelowBaseReserveReturnsBelowMinimum() async {
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        let check = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: BigInt(999_999))
        XCTAssertEqual(check, .belowMinimum(minimumXRP: "1"))
    }

    func testUnfundedAtOrAboveBaseReserveReturnsSatisfied() async {
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        // Exactly the base reserve activates the account — no error.
        let atReserve = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: BigInt(1_000_000))
        XCTAssertEqual(atReserve, .satisfied)

        // Above the base reserve — also no error.
        let aboveReserve = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: BigInt(5_000_000))
        XCTAssertEqual(aboveReserve, .satisfied)
    }

    func testLookupFailureReturnsUnknownFailOpen() async {
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .failure(URLError(.notConnectedToInternet))
        let service = makeService(client: client)

        // A transport failure fails OPEN on the form (no inline error) — the
        // Verify guard remains the fail-closed backstop.
        let check = await service.destinationReserveShortfall(address: "rUnknown", amountDrops: BigInt(1))
        XCTAssertEqual(check, .unknown)
    }

    func testNonActNotFoundLookupReturnsUnknownFailOpen() async {
        // A rate-limit (or any non-actNotFound RPC error) decodes with no
        // account_data — that is NOT proof the destination is unfunded, so the
        // form fails open rather than warn on an unverifiable account.
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"slowDown","error_message":"You are placing too much load on the server.","status":"error"}}
        """.utf8))
        let service = makeService(client: client)

        let check = await service.destinationReserveShortfall(address: "rUnknown", amountDrops: BigInt(1))
        XCTAssertEqual(check, .unknown)
    }

    func testThresholdTracksLiveBaseReserve() async {
        // A validator vote can raise the base reserve; the form minimum must
        // follow the live value, not the 1 XRP seed.
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 5_000_000, reserveInc: 1_000_000))
        let service = makeService(client: client)

        let check = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: BigInt(2_000_000))
        XCTAssertEqual(check, .belowMinimum(minimumXRP: "5"))
    }

    func testRepeatedAmountEditsHitNodeOnce() async {
        // The form re-validates on every amount keystroke, but funded/unfunded
        // is a property of the address. The per-address cache must collapse N
        // amount edits into a single `account_info` lookup.
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        for drops in [BigInt(100_000), BigInt(500_000), BigInt(999_999), BigInt(1_000_000)] {
            _ = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: drops)
        }

        XCTAssertEqual(client.accountInfoCallCount, 1, "amount edits must reuse the cached funding verdict")
    }

    func testForceRefreshRechecksNowFundedDestination() async {
        // A destination can fund mid-session. A cached `.unfunded` verdict would
        // keep the form blocking a below-reserve amount that the live Verify
        // guard now passes; the Continue path force-refreshes so the two agree.
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        let first = await service.destinationReserveShortfall(address: "rDest", amountDrops: BigInt(500_000))
        XCTAssertEqual(first, .belowMinimum(minimumXRP: "1"))
        XCTAssertEqual(client.accountInfoCallCount, 1)

        // The destination funds; the scripted node now reports account_data.
        client.accountInfoResult = .success(fundedAccountJSON(balance: "20000000"))

        let cached = await service.destinationReserveShortfall(address: "rDest", amountDrops: BigInt(500_000))
        XCTAssertEqual(cached, .belowMinimum(minimumXRP: "1"), "cached path serves the stale unfunded verdict")
        XCTAssertEqual(client.accountInfoCallCount, 1)

        let live = await service.destinationReserveShortfall(address: "rDest", amountDrops: BigInt(500_000), forceRefresh: true)
        XCTAssertEqual(live, .satisfied, "force-refresh sees the now-funded destination")
        XCTAssertEqual(client.accountInfoCallCount, 2)
    }

    func testFormThresholdMatchesVerifyGuard() async throws {
        // The whole point of reusing the shared reserve machinery: the form
        // minimum and the Verify-guard minimum are computed by identical code, so they can
        // never diverge — same value, same boundary.
        let client = ReserveCheckScriptedHTTPClient()
        client.accountInfoResult = .success(actNotFoundJSON())
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        let belowReserve = BigInt(999_999)
        let atReserve = BigInt(1_000_000)

        // Same amount below the reserve: the guard throws a minimum, the form
        // reports the same minimum.
        var guardMinimum: String?
        do {
            try await service.validateDestinationActivation(address: "rUnfunded", amountDrops: belowReserve)
            XCTFail("Verify guard must block below the base reserve")
        } catch let error as RippleSendError {
            guard case .destinationNotActivated(let minimumXRP) = error else {
                return XCTFail("unexpected RippleSendError: \(error)")
            }
            guardMinimum = minimumXRP
        }

        let formCheck = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: belowReserve)
        guard case .belowMinimum(let formMinimum) = formCheck else {
            return XCTFail("form check must flag below the base reserve, got \(formCheck)")
        }
        XCTAssertEqual(formMinimum, guardMinimum, "form and Verify thresholds must not diverge")

        // Same boundary: exactly the base reserve passes both.
        try await service.validateDestinationActivation(address: "rUnfunded", amountDrops: atReserve)
        let formAtReserve = await service.destinationReserveShortfall(address: "rUnfunded", amountDrops: atReserve)
        XCTAssertEqual(formAtReserve, .satisfied)
    }

    // MARK: - Fixtures

    private func makeService(client: HTTPClientProtocol) -> RippleService {
        RippleService(resolver: NoOverrideReserveResolver(), httpClient: client)
    }

    private func fundedAccountJSON(balance: String) -> Data {
        Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"\(balance)","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8)
    }

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

private struct NoOverrideReserveResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted HTTP client keyed on the `RippleAPI` endpoint, counting the
/// `account_info` calls so the cache-dedup test can assert the node is hit once.
private final class ReserveCheckScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    private let lock = NSLock()
    private(set) var accountInfoCallCount = 0

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            lock.lock()
            accountInfoCallCount += 1
            lock.unlock()
            return try respond(accountInfoResult)
        case .serverState:
            return try respond(serverStateResult)
        case .submit:
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
