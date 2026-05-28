//
//  CosmosUndelegateTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the `CosmosUndelegateTransactionBuilder` → `cosmosStakingPayload`
//  contract. The PR1 helper byte tests cover the on-wire format; this
//  suite covers the builder responsibility — payload-field discriminator,
//  bond-denom resolution, base-unit conversion, `TransactionBuilder`
//  defaults.
//

@testable import VultisigApp
import XCTest

final class CosmosUndelegateTransactionBuilderTests: XCTestCase {

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

    func testBuilderProducesUndelegatePayloadDiscriminator() {
        let builder = CosmosUndelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amount: "0.5",
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        let payload = builder.cosmosStakingPayload
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.opType, .undelegate)
        XCTAssertEqual(payload?.validatorAddress, "terravaloper1abc")
        XCTAssertEqual(payload?.denom, "uluna")
        // Half a LUNA at 6-decimals = 500,000 uluna.
        XCTAssertEqual(payload?.amount, "500000")
    }

    func testBuilderDefaultsToZeroMemoAndUnspecifiedTransactionType() {
        let builder = CosmosUndelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amount: "1",
            sendMaxAmount: true,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.memo, "")
        XCTAssertEqual(builder.transactionType, .unspecified)
        XCTAssertNil(builder.wasmContractPayload)
    }

    func testToAddressMirrorsValidatorOperator() {
        let builder = CosmosUndelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amount: "1",
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.toAddress, "terravaloper1abc")
    }
}
