//
//  CosmosDelegateTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the `CosmosDelegateTransactionBuilder` → `SendTransaction` →
//  `cosmosStakingPayload` contract. The PR1 helper byte tests cover wire
//  format; this suite covers the builder's responsibility — base-unit
//  conversion + payload-field discriminator + `TransactionBuilder` defaults.
//

@testable import VultisigApp
import XCTest

final class CosmosDelegateTransactionBuilderTests: XCTestCase {

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

    func testBuilderProducesDelegatePayloadWithCanonicalBondDenom() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: Decimal(string: "1.5") ?? 0,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        let payload = builder.cosmosStakingPayload
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.opType, .delegate)
        XCTAssertEqual(payload?.validatorAddress, "terravaloper1abc")
        XCTAssertEqual(payload?.denom, "uluna")
    }

    func testBuilderConvertsHumanDecimalToBaseUnits() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: Decimal(string: "1.5") ?? 0,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.cosmosStakingPayload?.amount, "1500000")
    }

    /// 1234.5 displays as "1,234.5" (or "1.234,5"); the signed amount must
    /// still be 1234.5, not the 1.234 a re-parse of that text produced.
    func testBuilderSignsAmountsAboveAThousandInFull() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: Decimal(string: "1234.5") ?? 0,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.cosmosStakingPayload?.amount, "1234500000")
    }

    func testBuilderEmitsEmptyMemoForCosmosStaking() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: 1,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.memo, "")
    }

    func testToAddressDefaultsToValidatorForVerifyScreenDisplay() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: 1,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        XCTAssertEqual(builder.toAddress, "terravaloper1abc")
    }

    func testBuildSendTransactionPropagatesStakingPayload() {
        let builder = CosmosDelegateTransactionBuilder(
            coin: Self.makeLunaCoin(),
            amountDecimal: 1,
            sendMaxAmount: false,
            validatorAddress: "terravaloper1abc"
        )
        let tx = builder.buildSendTransaction(vault: .example)
        XCTAssertNotNil(tx.cosmosStakingPayload)
        XCTAssertEqual(tx.cosmosStakingPayload?.opType, .delegate)
        XCTAssertTrue(tx.isStakingOperation)
    }
}
