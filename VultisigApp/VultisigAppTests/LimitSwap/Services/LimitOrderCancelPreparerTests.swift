//
//  LimitOrderCancelPreparerTests.swift
//  VultisigAppTests
//
//  What a cancel is allowed to cost, and what the user is told about it before
//  signing.
//
//  These moved off the deleted confirmation screen's view model. The screen went
//  because a cancel has no editable field — it arrives from the order card with
//  its assets, amounts and memo already fixed — but everything it CHECKED and
//  everything it SAID still has to happen, now on the way to Verify and on Verify
//  itself. That is what these pin.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelPreparerTests: XCTestCase {

    // MARK: - The THORChain route's fee is the whole cost

    /// The pre-flight must track the number the signer actually stamps, not a
    /// second copy of it that can drift — `thorchain.swift` hardcodes the deposit
    /// gas at signing regardless of what was fetched.
    func testFeeMatchesTheSignedDepositGas() {
        XCTAssertEqual(
            limitOrderCancelThorchainFee(decimals: 8),
            Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), 8)
        )
    }

    /// A dust balance is NOT sufficient. Gating on "> 0" would send the user to a
    /// Verify screen that fails at payload construction, with nothing on screen
    /// explaining why.
    func testDustBalanceCannotAffordTheDepositFee() {
        let fee = limitOrderCancelThorchainFee(decimals: 8)

        for balance in ["0", "1", String(THORChainConstants.depositGasBaseUnits - 1)] {
            XCTAssertLessThan(makeRune(balance: balance).balanceDecimal, fee, "balance \(balance)")
        }
    }

    /// Exactly the fee is enough — a THORChain cancel attaches no coins, so the
    /// deposit gas is the entire cost.
    func testExactlyTheFeeIsAffordable() {
        XCTAssertGreaterThanOrEqual(
            makeRune(balance: String(THORChainConstants.depositGasBaseUnits)).balanceDecimal,
            limitOrderCancelThorchainFee(decimals: 8)
        )
    }

    // MARK: - The disclosures that moved onto Verify

    /// ⚠️ The one that must never be dropped. An L1 cancel has to attach a coin
    /// for Bifrost to observe it at all, and THORNode donates whatever arrives to
    /// the pool with no refund path — up to two whole DOGE of the user's money.
    func testTheDonatedDustIsCarriedThroughToVerify() {
        let request = makeRequest().with(disclosures: LimitOrderCancelDisclosures(
            donatedAmount: "2 DOGE",
            balanceObjection: nil,
            canAffordCancel: true
        ))

        XCTAssertEqual(request.disclosures?.donatedAmount, "2 DOGE")
    }

    /// The THORChain route donates nothing, and must not imply that it does.
    func testTheThorchainRouteDeclaresNoDonatedDust() {
        let request = makeRequest().with(disclosures: LimitOrderCancelDisclosures(
            donatedAmount: nil,
            balanceObjection: nil,
            canAffordCancel: true
        ))

        XCTAssertNil(request.disclosures?.donatedAmount)
    }

    /// The duplicate-order warning rides the request from the moment the button
    /// is tapped, and survives the hop to Verify.
    func testTheDuplicateWarningSurvivesThePrepare() {
        let plain = makeRequest(duplicates: 0)
        let colliding = makeRequest(duplicates: 1)

        XCTAssertEqual(plain.with(disclosures: makeDisclosures()).duplicateRestingOrderCount, 0)
        XCTAssertEqual(colliding.with(disclosures: makeDisclosures()).duplicateRestingOrderCount, 1)
    }

    /// ⚠️ `with(disclosures:)` is a field-by-field copy, which is the shape that
    /// invites a silently dropped field. The memo in particular IS the signed
    /// bytes — losing it would address a different order, or none.
    func testAddingDisclosuresPreservesEverythingElse() {
        let original = makeRequest(duplicates: 3)

        let prepared = original.with(disclosures: makeDisclosures())

        XCTAssertEqual(prepared.orderId, original.orderId)
        XCTAssertEqual(prepared.inboundTxHash, original.inboundTxHash)
        XCTAssertEqual(prepared.memo, original.memo)
        XCTAssertEqual(prepared.sourceAsset, original.sourceAsset)
        XCTAssertEqual(prepared.targetAsset, original.targetAsset)
        XCTAssertEqual(prepared.sourceChainRawValue, original.sourceChainRawValue)
        XCTAssertEqual(prepared.duplicateRestingOrderCount, original.duplicateRestingOrderCount)
    }

    /// Nothing is disclosed until the preparer has run: the dust and the balance
    /// verdict both need the network. A request straight off the detail sheet
    /// therefore says nothing rather than saying "all clear".
    func testAnUnpreparedRequestCarriesNoDisclosures() {
        XCTAssertNil(makeRequest().disclosures)
    }

    // MARK: - Helpers

    private func makeRune(balance: String) -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
        coin.rawBalance = balance
        return coin
    }

    private func makeRequest(duplicates: Int = 0) -> LimitOrderCancelRequest {
        LimitOrderCancelRequest(
            orderId: "order-1",
            inboundTxHash: "ABC123",
            memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            sourceChainRawValue: Chain.thorChain.rawValue,
            duplicateRestingOrderCount: duplicates
        )
    }

    private func makeDisclosures() -> LimitOrderCancelDisclosures {
        LimitOrderCancelDisclosures(donatedAmount: nil, balanceObjection: nil, canAffordCancel: true)
    }
}
