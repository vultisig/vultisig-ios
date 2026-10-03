//
//  SwapKitNearTests.swift
//  VultisigAppTests
//
//  NEAR source via SwapKit NEAR-Intents: a `simpleTransfer` deposit to a
//  per-swap implicit account. iOS asks `/v3/swap` not to build a transaction
//  (as the SDK does) and signs its own frozen transfer, so the cosigning
//  payload is identical on every platform. A response that still carries a
//  built NEAR body is turned away.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitNearTests: XCTestCase {

    func testRealNearSwapFixtureDecodesAsDepositOnly() throws {
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: "v3-real-near-swap")

        XCTAssertEqual(response.sellAsset, "NEAR.NEAR")
        XCTAssertEqual(response.providers, ["NEAR"])
        XCTAssertEqual(response.meta.txType, "")
        guard case .nearDepositOnly = response.tx else {
            return XCTFail("expected .nearDepositOnly, got \(response.tx)")
        }
        XCTAssertEqual(response.targetAddress, "14397e36f7e4f15599c8ba31baac5fbfd79b415729428ba70d94aee794a4f27f")
        XCTAssertNoThrow(try SwapKitService.validateSigningCapability(response: response, fromChain: .near))
    }

    func testABuiltNearBodyIsTurnedAway() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: SwapKitFixtureLoader.loadData("v3-real-near-swap")) as? [String: Any]
        )
        var meta = try XCTUnwrap(json["meta"] as? [String: Any])
        meta["txType"] = "NEAR"
        json["meta"] = meta
        json["tx"] = "DAAAAHJlbGF5LmF1cm9yYQ=="

        let response = try JSONDecoder().decode(
            SwapKitSwapResponse.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        guard case .unsupported = response.tx else {
            return XCTFail("expected .unsupported, got \(response.tx)")
        }
        XCTAssertThrowsError(try SwapKitService.validateSigningCapability(response: response, fromChain: .near))
    }

    func testNearIsASwapKitSourceAndDestination() {
        XCTAssertTrue(SwapKitCapability.canReceive(on: .near))
        XCTAssertTrue(SwapKitCapability.canQuote(from: .near))
        XCTAssertTrue(SwapKitCapability.canSign(.nearDepositOnly, from: .near))
        XCTAssertFalse(SwapKitCapability.canSign(.rippleDepositOnly, from: .near))
        XCTAssertEqual(SwapKitChainIDMapper.swapKitChainId(for: .near), "near")
        XCTAssertEqual(SwapKitChainIDMapper.chain(forSwapKitChain: "NEAR"), .near)
    }

    func testNearSourceGateCoversTheGasReservationAndTheStorageReserve() throws {
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: "v3-real-near-swap")
        let near = Coin(
            asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24, isNativeToken: true),
            address: "14397e36f7e4f15599c8ba31baac5fbfd79b415729428ba70d94aee794a4f27f",
            hexPublicKey: ""
        )
        near.rawBalance = "1000000000000000000000000" // 1 NEAR
        let vm = SwapDetailsViewModel()
        vm.fromCoin = near
        vm.fromCoins = [near]
        // SwapKit's wire inbound fee: 0.0008 NEAR.
        vm.quote = .swapkit(response, fee: BigInt("800000000000000000000"), subProvider: "NEAR")
        // nearcore gas reservation for an implicit receiver at 1e8 yocto/gas (`Near.implicitGasFee`).
        vm.thorchainFee = BigInt("7607442456250000000000")
        vm.gas = vm.thorchainFee
        // 1,000 bytes of storage at 1e19 yocto per byte: 0.01 NEAR.
        vm.storageReserve = BigInt("10000000000000000000000")
        // Balance − storage reserve − wire fee: affordable only if the wire fee were the cost.
        vm.fromAmount = "0.9892"

        XCTAssertEqual(vm.balanceError, .insufficientGas)
    }

    func testOnlyADepositOnlyRequestAsksSwapKitNotToBuild() throws {
        let plain = SwapKitSwapRequest(routeId: "r", sourceAddress: "s", destinationAddress: "d", overrideSlippage: nil)
        let depositOnly = SwapKitSwapRequest(
            routeId: "r",
            sourceAddress: "s",
            destinationAddress: "d",
            overrideSlippage: nil,
            disableBuildTx: true,
            disableBalanceCheck: true
        )

        let plainBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any]
        )
        let depositBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(depositOnly)) as? [String: Any]
        )

        XCTAssertNil(plainBody["disableBuildTx"])
        XCTAssertNil(plainBody["disableBalanceCheck"])
        XCTAssertEqual(depositBody["disableBuildTx"] as? Bool, true)
        XCTAssertEqual(depositBody["disableBalanceCheck"] as? Bool, true)
    }
}
