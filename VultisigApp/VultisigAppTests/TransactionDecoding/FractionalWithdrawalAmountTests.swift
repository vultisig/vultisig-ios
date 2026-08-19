//
//  FractionalWithdrawalAmountTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class FractionalWithdrawalAmountTests: XCTestCase {

    private func tcy(address: String = "thor1vault") -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "TCY", logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: address, hexPublicKey: "hex"
        )
    }

    private func fraction(_ bps: Int) -> DecodedTransaction {
        DecodedTransaction(
            operation: .unstake,
            amount: .fraction(basisPoints: bps, of: .transactionCoin),
            evidence: .memo
        )
    }

    /// The endpoint returns base units. Scale those exactly once, then apply the
    /// same position × bps / 10000 arithmetic as the initiator.
    func testResolvesTheSameFigureTheInitiatorWouldShow() async {
        let amount = await FractionalWithdrawalAmount.resolve(
            for: fraction(5006), coin: tcy(),
            readStakedRaw: { _ in Decimal(200_274_000_000) }
        )
        XCTAssertEqual(amount?.ticker, "TCY")
        // Grouped exactly as the initiator's QuotedWithdrawalPresentation renders
        // it (same formatToDecimal), so the two devices show the identical string.
        XCTAssertTrue(
            amount?.amount.hasPrefix("1,002.571644") ?? false,
            "expected 1,002.571644…, got \(amount?.amount ?? "nil")"
        )
    }

    @MainActor
    func testResolvedFigureIncludesFiat() async throws {
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "tcy", value: 0.05)
        ])
        let amount = await FractionalWithdrawalAmount.resolve(
            for: fraction(5000), coin: tcy(),
            readStakedRaw: { _ in Decimal(200_000_000_000) }
        )

        XCTAssertEqual(amount?.amount, "1,000")
        XCTAssertFalse(amount?.fiat?.isEmpty ?? true)
    }

    /// A read that comes back empty leaves the screen showing the verb alone.
    func testNilWhenNothingIsStaked() async {
        let amount = await FractionalWithdrawalAmount.resolve(
            for: fraction(5006), coin: tcy(), readStakedRaw: { _ in 0 }
        )
        XCTAssertNil(amount)
    }

    /// An absolute amount is already in the signed content; no position read applies.
    func testNilForAnAbsoluteAmount() async {
        let decoded = DecodedTransaction(
            operation: .unstake,
            amount: .units(BigInt(100), of: .transactionCoin),
            evidence: .memo
        )
        let amount = await FractionalWithdrawalAmount.resolve(
            for: decoded, coin: tcy(), readStakedRaw: { _ in Decimal(100_000_000_000) }
        )
        XCTAssertNil(amount, "an absolute amount needs no position read")
    }

    /// The position read is of the SIGNER'S OWN address — derived on this device,
    /// not anything the initiator supplied.
    func testReadsTheSignersOwnAddress() async {
        var queried: String?
        _ = await FractionalWithdrawalAmount.resolve(
            for: fraction(10_000), coin: tcy(address: "thor1me"),
            readStakedRaw: { addr in queried = addr; return Decimal(50_000_000_000) }
        )
        XCTAssertEqual(queried, "thor1me")
    }
}
