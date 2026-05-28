//
//  CosmosRedelegateTransactionBuilderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class CosmosRedelegateTransactionBuilderTests: XCTestCase {

    private static func makeLunaCoin() -> Coin {
        let meta = CoinMeta(
            chain: .terra,
            ticker: "LUNA",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna-2",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    func testRedelegatePayloadCarriesSrcAndDst() {
        let builder = CosmosRedelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amount: "1",
            sendMaxAmount: false,
            validatorSrcAddress: "terravaloper1src",
            validatorDstAddress: "terravaloper1dst"
        )
        let payload = builder.cosmosStakingPayload
        XCTAssertEqual(payload?.opType, .redelegate)
        XCTAssertEqual(payload?.validatorSrcAddress, "terravaloper1src")
        XCTAssertEqual(payload?.validatorDstAddress, "terravaloper1dst")
        XCTAssertNil(payload?.validatorAddress)
        XCTAssertEqual(payload?.amount, "1000000")
        XCTAssertEqual(payload?.denom, "uluna")
    }

    func testToAddressIsDestination() {
        let builder = CosmosRedelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amount: "1",
            sendMaxAmount: false,
            validatorSrcAddress: "terravaloper1src",
            validatorDstAddress: "terravaloper1dst"
        )
        XCTAssertEqual(builder.toAddress, "terravaloper1dst")
    }
}
