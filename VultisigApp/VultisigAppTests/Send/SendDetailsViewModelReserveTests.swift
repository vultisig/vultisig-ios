//
//  SendDetailsViewModelReserveTests.swift
//  VultisigAppTests
//
//  Covers the inline XRP base-reserve check on the send form: an unfunded
//  destination below the live base reserve sets an inline warning and blocks
//  Continue (same threshold as the Verify guard), while a funded
//  destination, an amount at/above the reserve, and a lookup failure all
//  proceed (fail open — the Verify guard is the fail-closed backstop). The
//  check is XRP-native-only.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SendDetailsViewModelReserveTests: XCTestCase {

    // MARK: - Continue (validateForm) path

    func testUnfundedBelowReserveSetsInlineWarningAndBlocksContinue() async {
        let vm = makeXRPVM(service: unfundedService(reserveBase: 1_000_000, reserveInc: 200_000))
        vm.toAddress = "rUnfundedDestination"
        vm.amount = "0.5" // 500_000 drops < 1 XRP base reserve

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid, "a below-reserve unfunded XRP send must block Continue")
        // Locale-independent: the warning is the shared activation copy with
        // the live 1 XRP minimum interpolated — the same string the Verify
        // guard would present.
        let expected = String(format: "xrpDestinationNotActivatedError".localized, "1")
        XCTAssertEqual(vm.destinationReserveWarning, expected)
    }

    func testFundedDestinationNoWarning() async {
        let vm = makeXRPVM(service: fundedService())
        vm.toAddress = "rFundedDestination"
        vm.amount = "0.5"

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid, "a funded destination has no activation minimum")
        XCTAssertNil(vm.destinationReserveWarning)
    }

    func testUnfundedAtReserveNoWarning() async {
        let vm = makeXRPVM(service: unfundedService(reserveBase: 1_000_000, reserveInc: 200_000))
        vm.toAddress = "rUnfundedDestination"
        vm.amount = "1" // exactly the base reserve activates the account

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid, "an amount at the base reserve is valid")
        XCTAssertNil(vm.destinationReserveWarning)
    }

    func testLookupFailureNoWarningFailOpen() async {
        let vm = makeXRPVM(service: failingService())
        vm.toAddress = "rUnverifiableDestination"
        vm.amount = "0.5"

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid, "form fails open on a lookup failure — the Verify guard blocks instead")
        XCTAssertNil(vm.destinationReserveWarning)
    }

    func testNonRippleChainSkipsReserveCheck() async {
        // A BTC VM with an unfunded-scripted RippleService: the chain guard
        // must short-circuit so the service is never consulted.
        let vm = SendFormFixture.make(
            coin: SendFormFixture.makeBTC(),
            addressResolver: { input, _ in input },
            rippleService: unfundedService(reserveBase: 1_000_000, reserveInc: 200_000)
        )
        vm.toAddress = "bc1qexample"
        vm.amount = "0.5"

        let blocked = await vm.validateDestinationReserve()

        XCTAssertTrue(blocked, "non-XRP chains skip the reserve rule")
        XCTAssertNil(vm.destinationReserveWarning)
    }

    // MARK: - While-typing (updateDestinationReserveWarning) path

    func testUpdateWarningSetWhenBelowReserveAndAddressValid() async {
        let vm = makeXRPVM(service: unfundedService(reserveBase: 1_000_000, reserveInc: 200_000))
        vm.toAddress = Self.validXRPAddress
        vm.amount = "0.25"

        await vm.updateDestinationReserveWarning()

        XCTAssertNotNil(vm.destinationReserveWarning)
    }

    func testUpdateWarningClearedForInvalidAddress() async {
        let vm = makeXRPVM(service: unfundedService(reserveBase: 1_000_000, reserveInc: 200_000))
        vm.toAddress = "rNotAValidXRPAddress" // malformed → no node lookup
        vm.amount = "0.25"

        await vm.updateDestinationReserveWarning()

        XCTAssertNil(vm.destinationReserveWarning,
                     "no lookup until the address is a well-formed destination AND an amount is entered")
    }

    // MARK: - Reset

    func testResetClearsReserveWarning() {
        let vm = makeXRPVM(service: fundedService())
        vm.destinationReserveWarning = "stale warning"

        vm.reset(to: SendFormFixture.makeXRP())

        XCTAssertNil(vm.destinationReserveWarning)
    }

    // MARK: - Fixtures

    /// A well-formed mainnet XRP classic address (the XRPL genesis account),
    /// used where `shouldCheckDestinationReserve` requires real format validity.
    private static let validXRPAddress = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"

    private func makeXRPVM(service: RippleService) -> SendDetailsViewModel {
        SendFormFixture.make(
            coin: SendFormFixture.makeXRP(rawBalance: "20000000"), // 20 XRP
            addressResolver: { input, _ in input },
            rippleService: service
        )
    }

    private func unfundedService(reserveBase: Int, reserveInc: Int) -> RippleService {
        let client = RippleScriptedClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """.utf8))
        client.serverStateResult = .success(Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":\(reserveBase),"reserve_inc":\(reserveInc)}}}}
        """.utf8))
        return RippleService(resolver: NoOverrideResolver(), httpClient: client)
    }

    private func fundedService() -> RippleService {
        let client = RippleScriptedClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"20000000","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8))
        return RippleService(resolver: NoOverrideResolver(), httpClient: client)
    }

    private func failingService() -> RippleService {
        let client = RippleScriptedClient()
        client.accountInfoResult = .failure(URLError(.notConnectedToInternet))
        return RippleService(resolver: NoOverrideResolver(), httpClient: client)
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

private final class RippleScriptedClient: HTTPClientProtocol, @unchecked Sendable {
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
