//
//  NoonYieldProviderTests.swift
//  VultisigAppTests
//
//  Covers the Noon redemption state machine: how the on-chain read snapshot
//  maps to redemption rows (none/pending/claimable) and how the weekly
//  settlement date is derived for the pending-state copy.
//

import BigInt
import XCTest
@testable import VultisigApp

final class NoonYieldProviderTests: XCTestCase {

    private let sampleUser = "0x8b937c5395d95a8c8948c7c5b844e1541798d90c"

    private func usdcCoin() -> Coin {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: NoonConstants.assetDecimals,
            priceProviderId: "usd-coin",
            contractAddress: NoonConstants.usdcMainnet,
            isNativeToken: false
        )
        return Coin(asset: asset, address: sampleUser, hexPublicKey: "HexPublicKeyExample")
    }

    private func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Bundled approve gating

    func testDepositBundlesApproveWhenAllowanceShort() throws {
        let amount = BigInt(100_000_000)
        let approve = NoonYieldProvider.depositApprovePayload(allowance: BigInt(0), amount: amount)
        let payload = try XCTUnwrap(approve)
        XCTAssertEqual(payload.amount, amount)
        XCTAssertEqual(
            payload.spender.lowercased(),
            NoonConstants.vaultAddress.lowercased(),
            "the approve spender must be the vault"
        )
    }

    func testDepositSkipsApproveWhenAllowanceSufficient() {
        let amount = BigInt(100_000_000)
        // Allowance exactly covers, and strictly exceeds: both skip the approve.
        XCTAssertNil(NoonYieldProvider.depositApprovePayload(allowance: amount, amount: amount))
        XCTAssertNil(NoonYieldProvider.depositApprovePayload(allowance: BigInt(200_000_000), amount: amount))
    }

    /// The bundled approve's (spender, amount) must reproduce the SDK golden
    /// `approve(vault, amount)` calldata (selector 0x095ea7b3) byte-for-byte.
    func testBundledApproveMatchesGoldenCalldata() throws {
        let amount = BigInt(100_000_000)
        let approve = try XCTUnwrap(
            NoonYieldProvider.depositApprovePayload(allowance: BigInt(0), amount: amount)
        )
        // Re-encode the same (spender, amount) the bundled approve authorizes.
        XCTAssertEqual(approve.spender.lowercased(), NoonConstants.vaultAddress.lowercased())
        let calldata = try NoonService.shared.encodeUsdcApprove(amount: approve.amount)
        XCTAssertEqual(
            hex(calldata),
            "0x095ea7b3000000000000000000000000a73424f1ac94b3ef0d0c9af4f2967c87d4af25d90000000000000000000000000000000000000000000000000000000005f5e100"
        )
    }

    // MARK: - Generic deposit payload (calldata in quote.tx)

    func testGenericDepositPayloadCarriesDepositCalldataByteEqual() throws {
        let amount = BigInt(100_000_000)
        let depositData = try NoonService.shared.encodeDeposit(assets: amount, receiver: sampleUser)
        let depositHex = hex(depositData)

        let payload = NoonYieldProvider.makeGenericDepositPayload(
            usdcCoin: usdcCoin(),
            sender: sampleUser,
            depositDataHex: depositHex,
            depositAmount: amount,
            gasPrice: BigInt(20_000_000_000),
            gasLimit: BigInt(300_000)
        )

        // The deposit call rides quote.tx, byte-equal to the SDK golden vector.
        XCTAssertEqual(
            payload.quote.tx.data,
            "0x6e553f650000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
        )
        XCTAssertEqual(payload.quote.tx.to.lowercased(), NoonConstants.vaultAddress.lowercased())
        XCTAssertEqual(payload.quote.tx.value, "0", "a Noon deposit sends no ETH value")
        XCTAssertEqual(payload.quote.tx.gasPrice, "20000000000")
        XCTAssertEqual(payload.quote.tx.gas, Int64(300_000))
        XCTAssertEqual(payload.fromCoin.ticker, "USDC")
        XCTAssertEqual(payload.fromAmount, amount)
        XCTAssertEqual(payload.provider, .oneInch)
    }

    // MARK: - Redemption derivation

    func testNoRedemptionWhenStateNone() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(0),
            currentAssets: BigInt(0),
            claimableAssets: BigInt(0),
            claimableRedeemShares: BigInt(0),
            pendingRedeemShares: BigInt(0),
            redemptionState: .none
        )
        XCTAssertTrue(NoonYieldProvider.deriveRedemptions(from: position).isEmpty)
    }

    func testPendingRedemptionCarriesSettlementDate() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(98_333_202),
            currentAssets: BigInt(101_000_000),
            claimableAssets: BigInt(0),
            claimableRedeemShares: BigInt(0),
            pendingRedeemShares: BigInt(98_333_202),
            redemptionState: .pending
        )

        let redemptions = NoonYieldProvider.deriveRedemptions(from: position)
        XCTAssertEqual(redemptions.count, 1)
        let redemption = redemptions[0]
        XCTAssertEqual(redemption.status, .pending)
        XCTAssertEqual(redemption.amount, Decimal(string: "98.333202"))
        XCTAssertNotNil(redemption.claimableAt, "a pending redemption must carry a settlement date")
        XCTAssertFalse(redemption.isClaimable, "a future-dated pending redemption is not yet claimable")
    }

    func testClaimableRedemptionIsImmediatelyClaimable() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(96_000_000),
            currentAssets: BigInt(97_617_839),
            claimableAssets: BigInt(97_617_839),
            claimableRedeemShares: BigInt(96_000_000),
            pendingRedeemShares: BigInt(0),
            redemptionState: .claimable
        )

        let redemptions = NoonYieldProvider.deriveRedemptions(from: position)
        XCTAssertEqual(redemptions.count, 1)
        let redemption = redemptions[0]
        XCTAssertEqual(redemption.status, .claimable)
        XCTAssertEqual(redemption.amount, Decimal(string: "97.617839"))
        XCTAssertNil(redemption.claimableAt, "a claimable redemption has no remaining wait")
        XCTAssertTrue(redemption.isClaimable)
    }

    // MARK: - Redeem share denomination (assets → shares)

    /// The withdraw form is denominated in USDC (assets) but requestRedeem burns
    /// SHARES. A FULL withdraw must redeem the exact share balance — never the
    /// (larger, appreciated) asset value, which would ask to burn more shares
    /// than the owner holds and revert during gas estimation. Regression guard
    /// for the reverted withdraw.
    func testFullWithdrawRedeemsShareBalanceNotAssets() {
        let shareBalance = BigInt(96_000_000)
        let positionAssets = BigInt(97_617_839)   // appreciated: assets > shares
        XCTAssertEqual(
            NoonYieldProvider.sharesToRedeem(assets: positionAssets, shareBalance: shareBalance, positionAssets: positionAssets),
            shareBalance
        )
    }

    func testOverWithdrawClampsToShareBalance() {
        let shareBalance = BigInt(96_000_000)
        let positionAssets = BigInt(97_617_839)
        XCTAssertEqual(
            NoonYieldProvider.sharesToRedeem(assets: BigInt(200_000_000), shareBalance: shareBalance, positionAssets: positionAssets),
            shareBalance,
            "an amount above the position value can never redeem more than the balance"
        )
    }

    func testPartialWithdrawRedeemsProportionalShares() {
        // sharePrice 2.0 for an exact split: half the assets ⇒ half the shares.
        XCTAssertEqual(
            NoonYieldProvider.sharesToRedeem(assets: BigInt(50_000_000), shareBalance: BigInt(50_000_000), positionAssets: BigInt(100_000_000)),
            BigInt(25_000_000),
            "redeeming half the asset value redeems half the shares"
        )
    }

    func testWithdrawWithZeroShareBalanceRedeemsNothing() {
        XCTAssertEqual(
            NoonYieldProvider.sharesToRedeem(assets: BigInt(100_000_000), shareBalance: BigInt(0), positionAssets: BigInt(0)),
            BigInt(0)
        )
    }

    // MARK: - Claim guard

    @MainActor
    func testBuildClaimPayloadRejectsPendingRedemption() async {
        // A pending redemption's `amount` is in SHARE units; claiming it would
        // mis-denominate the withdraw, so the guard must reject it before any
        // network read or signed-bytes construction.
        let provider = NoonYieldProvider()
        let pending = YieldRedemption(
            id: "noon_pending",
            amount: Decimal(string: "98.333202") ?? .zero,
            requestedAt: Date(),
            claimableAt: nil,
            status: .pending
        )

        do {
            _ = try await provider.buildClaimPayload(
                vault: .example,
                recipient: "0x0000000000000000000000000000000000000001",
                redemption: pending
            )
            XCTFail("buildClaimPayload must reject a non-claimable redemption")
        } catch {
            // Expected — the guard throws up front.
        }
    }

    // MARK: - Deposit form minimum (100 USDC, not MIN_AMOUNT_WEI)

    func testProviderExposesHundredUsdcDepositMinimum() {
        let provider = NoonYieldProvider()
        XCTAssertEqual(
            provider.minDepositAmount,
            Decimal(100),
            "the deposit form must enforce the 100 USDC product minimum, not the 0.01 USDC dust floor"
        )
    }

    /// The deposit form's `validForm` maps `amountField.validate()` to a bool, so a
    /// throwing validate ⇒ `validForm == false`. Build the field with the same
    /// validators `YieldDepositViewModel.onLoad` installs and confirm a sub-100
    /// amount fails while 100 (and above) passes.
    private func makeDepositAmountField() -> FormField {
        let field = FormField(
            label: "amount",
            placeholder: "0",
            validators: [RequiredValidator(errorMessage: "required")]
        )
        field.validators.append(MinAmountValidator(minimum: Decimal(100), errorMessage: "min"))
        field.validators.append(AmountBalanceValidator(balance: Decimal(1_000)))
        return field
    }

    func testDepositFormInvalidBelowMinimum() {
        let field = makeDepositAmountField()
        field.value = "50"
        XCTAssertThrowsError(try field.validate(), "a sub-100 USDC amount must make validForm false")
    }

    func testDepositFormValidAtAndAboveMinimum() {
        let atMin = makeDepositAmountField()
        atMin.value = "100"
        XCTAssertNoThrow(try atMin.validate(), "exactly 100 USDC must be accepted")

        let aboveMin = makeDepositAmountField()
        aboveMin.value = "250"
        XCTAssertNoThrow(try aboveMin.validate(), "above the minimum must be accepted")
    }

    func testMinAmountValidatorPassesEmptyValue() {
        // Empty defers to RequiredValidator; the min validator must not throw on it.
        let validator = MinAmountValidator(minimum: Decimal(100), errorMessage: "min")
        XCTAssertNoThrow(try validator.validate(value: ""))
    }

    // MARK: - Estimated-yield preview math

    /// APY is reported as a PERCENT (`ir.7d.net.apy_pct`), so the projection must
    /// divide by 100: yearly = amount × apy/100, monthly = yearly / 12.
    func testYieldEstimateConvertsApyPercentToFraction() throws {
        // 1000 USDC at 12% APY ⇒ 120 / year, 10 / month.
        let estimate = try XCTUnwrap(
            YieldEstimate.make(amount: Decimal(1_000), apyPercent: Decimal(12))
        )
        XCTAssertEqual(estimate.yearly, Decimal(120), "yearly = amount × apy/100")
        XCTAssertEqual(estimate.monthly, Decimal(10), "monthly = yearly / 12")
    }

    func testYieldEstimateHandlesFractionalApy() throws {
        // 250 USDC at 8.4% APY ⇒ 21 / year, 1.75 / month.
        let estimate = try XCTUnwrap(
            YieldEstimate.make(amount: Decimal(250), apyPercent: Decimal(string: "8.4"))
        )
        XCTAssertEqual(estimate.yearly, Decimal(21))
        XCTAssertEqual(estimate.monthly, Decimal(string: "1.75"))
    }

    func testYieldEstimateNilWhenAmountMissingOrZero() {
        XCTAssertNil(YieldEstimate.make(amount: nil, apyPercent: Decimal(12)))
        XCTAssertNil(YieldEstimate.make(amount: Decimal(0), apyPercent: Decimal(12)))
    }

    func testYieldEstimateNilWhenApyMissingOrZero() {
        XCTAssertNil(YieldEstimate.make(amount: Decimal(1_000), apyPercent: nil))
        XCTAssertNil(YieldEstimate.make(amount: Decimal(1_000), apyPercent: Decimal(0)))
    }

    // MARK: - Settlement date

    func testNextSettlementDateIsWednesdayPlusSettlementWindowUtc() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        // A Monday — the next Wednesday window close is 2 days out, settling +7.
        let monday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))
        )

        let settlement = try XCTUnwrap(NoonYieldProvider.nextSettlementDate(now: monday))
        let components = calendar.dateComponents([.weekday, .hour], from: settlement)
        // Close is Wednesday (weekday 4); +7 days lands on a Wednesday again.
        XCTAssertEqual(components.weekday, 4)
        XCTAssertEqual(components.hour, NoonConstants.RedemptionWindow.closesHourUtc)
        XCTAssertGreaterThan(settlement, monday)
    }
}
