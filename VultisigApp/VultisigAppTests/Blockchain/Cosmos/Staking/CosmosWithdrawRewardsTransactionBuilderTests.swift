//
//  CosmosWithdrawRewardsTransactionBuilderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class CosmosWithdrawRewardsTransactionBuilderTests: XCTestCase {

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

    func testSingleValidatorPayload() {
        let builder = CosmosWithdrawRewardsTransactionBuilder(
            coin: Self.makeLunaCoin(),
            validatorAddresses: ["terravaloper1a"]
        )
        let payload = builder.cosmosStakingPayload
        XCTAssertEqual(payload?.opType, .withdrawRewards)
        XCTAssertEqual(payload?.validators, ["terravaloper1a"])
        XCTAssertEqual(payload?.denom, "uluna")
        XCTAssertNil(payload?.amount, "MsgWithdrawDelegatorReward carries no Coin")
    }

    func testMultiValidatorPayloadPreservesOrder() {
        let validators = (1...8).map { "terravaloper1val\($0)" }
        let builder = CosmosWithdrawRewardsTransactionBuilder(
            coin: Self.makeLunaCoin(),
            validatorAddresses: validators
        )
        let payload = builder.cosmosStakingPayload
        XCTAssertEqual(payload?.validators, validators)
    }

    func testEmptyValidatorsProducesNilPayload() {
        let builder = CosmosWithdrawRewardsTransactionBuilder(
            coin: Self.makeLunaCoin(),
            validatorAddresses: []
        )
        XCTAssertNil(builder.cosmosStakingPayload)
    }
}
