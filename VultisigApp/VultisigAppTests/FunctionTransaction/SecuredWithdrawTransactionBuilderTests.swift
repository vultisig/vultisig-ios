//
//  SecuredWithdrawTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the THORChain secured-asset redemption (`SECURE-`): the exact memo, and
//  — the part that costs money if it drifts — the attached amount, which unlike
//  the node memos next door is a real transfer. Carries over the golden
//  fixtures from the deleted `FunctionCallWithdrawSecuredAssetTests` and the
//  `testWithdrawSecuredAssetParity` case, both of which captured the legacy
//  sub-model verbatim.
//

@testable import VultisigApp
import XCTest

final class SecuredWithdrawTransactionBuilderTests: XCTestCase {

    private static let btcDestination = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"

    /// Built through `SecuredAssetMapper`, the same derivation production uses,
    /// so the denom → ticker / decimals / `isNativeToken` mapping the deposit
    /// signer reads is exercised rather than hand-written.
    static func makeSecuredCoin(denom: String, rawBalance: String = "100000000") -> Coin {
        let meta = SecuredAssetMapper.coinMeta(forDenom: denom)
        let coin = Coin(asset: meta, address: FunctionCallFixture.thorAddress, hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private static func makeBuilder(
        denom: String = "btc-btc",
        destination: String = btcDestination,
        amount: Decimal = 1
    ) -> SecuredWithdrawTransactionBuilder {
        SecuredWithdrawTransactionBuilder(
            coin: makeSecuredCoin(denom: denom),
            destinationAddress: destination,
            withdrawAmount: amount
        )
    }

    // MARK: - Memo (golden fixture)

    /// Pin: the legacy `FunctionCallWithdrawSecuredAsset.toString()` returned
    /// `SECURE-:<destinationAddress>` — one segment, no amount, no asset. The
    /// asset is named by the deposit's coin, not by the memo.
    func testMemoIsSecureMinusFollowedByTheDestinationAddress() {
        XCTAssertEqual(Self.makeBuilder().memo, "SECURE-:\(Self.btcDestination)")
    }

    /// The deleted test's own fixture string, kept verbatim so the shape is
    /// pinned independently of what a valid address looks like.
    func testMemoMatchesTheLegacyFixtureVerbatim() {
        let builder = Self.makeBuilder(destination: "0xL1DestAddr")
        XCTAssertEqual(builder.memo, "SECURE-:0xL1DestAddr")
    }

    /// The memo names the L1 payout address, never the THORChain account the
    /// deposit is signed from — that is the whole point of the operation.
    func testMemoCarriesTheDestinationNotTheSigningAddress() {
        let builder = Self.makeBuilder()
        XCTAssertFalse(builder.memo.contains(builder.coin.address))
    }

    // MARK: - Attached amount (fund safety)

    /// `SendTransaction.amountInRaw` reads this as a human decimal and
    /// multiplies by `10^decimals`. Legacy attached
    /// `amount.formatToDecimal(digits: coin.decimals)`, so the redemption burns
    /// exactly what the user typed.
    func testAttachedAmountIsTheRequestedAmountAsAHumanDecimal() {
        XCTAssertEqual(Self.makeBuilder(amount: 1).amount, "1")
        XCTAssertEqual(Self.makeBuilder(amount: Decimal(string: "0.5")!).amount, "0.5")
        XCTAssertFalse(Self.makeBuilder().sendMaxAmount)
    }

    /// Secured assets are pinned to 8 decimals by `THORChainTokenMetadataFactory`,
    /// so one base unit is 1e-8 and has to survive formatting intact.
    func testSmallestRepresentableAmountSurvivesFormatting() {
        let builder = Self.makeBuilder(amount: Decimal(string: "0.00000001")!)
        XCTAssertEqual(builder.coin.decimals, 8)
        XCTAssertEqual(builder.amount, "0.00000001")
    }

    /// `formatToDecimal` truncates rather than rounds — the ninth decimal is
    /// dropped, matching the legacy conversion.
    func testSubBaseUnitPrecisionIsTruncatedNotRounded() {
        let builder = Self.makeBuilder(amount: Decimal(string: "1.234567899")!)
        XCTAssertEqual(builder.amount, "1.23456789")
    }

    /// A redemption never sweeps: `sendMaxAmount` stays false regardless, so
    /// nothing downstream reinterprets the amount as "all of it".
    func testRedemptionNeverSendsMax() {
        XCTAssertFalse(Self.makeBuilder(amount: 1_000).sendMaxAmount)
    }

    // MARK: - Memo dictionary (golden fixture)

    /// Pin: legacy `toDictionary()` wrote exactly three entries — `operation`,
    /// `memo` and `destinationAddress`. A non-empty dictionary is also what
    /// makes `SendCryptoLogic.isDeposit` true on THORChain, which is what
    /// routes this to the secured-aware `MsgDeposit` builder rather than to a
    /// self-addressed bank send.
    func testMemoDictionaryMatchesTheLegacyThreeEntries() {
        let dict = Self.makeBuilder(destination: "0xL1DestAddr").memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["operation"], "withdraw")
        XCTAssertEqual(dict["destinationAddress"], "0xL1DestAddr")
        XCTAssertEqual(dict["memo"], "SECURE-:0xL1DestAddr")
        XCTAssertEqual(dict.count, 3)
    }

    // MARK: - The redeemed coin

    /// The deposit has to be signed against the secured token, whose
    /// `contractAddress` is the denom: `buildThorchainDepositMessage` derives
    /// `asset.chain` / `asset.symbol` / `asset.secured` from exactly that.
    func testTheRedeemedCoinIsTheSecuredTokenNotTheNativeAsset() {
        let builder = Self.makeBuilder(denom: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertTrue(THORChainHelper.isSecuredAsset(coin: builder.coin))
        XCTAssertFalse(builder.coin.isNativeToken)
        XCTAssertEqual(builder.coin.ticker, "USDC")
        XCTAssertEqual(THORChainHelper.securedAssetChain(coin: builder.coin), "ETH")
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary produced the memo, the amount, `.unspecified`
    /// and an **empty** `toAddress` even though a destination exists — a
    /// `MsgDeposit` is addressed by its memo. `FunctionCallInstance.toAddress`
    /// returned nil for this case for the same reason.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE()])
        let builder = Self.makeBuilder(destination: "0xL1DestAddr", amount: 2)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "SECURE-:0xL1DestAddr")
        XCTAssertEqual(tx.amount, "2")
        XCTAssertEqual(tx.coin.ticker, "BTC")
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "SECURE-:0xL1DestAddr")
        XCTAssertEqual(tx.memoFunctionDictionary["operation"], "withdraw")
        XCTAssertEqual(tx.memoFunctionDictionary["destinationAddress"], "0xL1DestAddr")
        // Builders never take gas; `FunctionTransactionScreen.onVerify` fetches
        // it before the verify screen. The legacy sub-model took it as a
        // parameter.
        XCTAssertEqual(tx.gas, .zero)
    }

    /// The attached amount reaches the signer as base units of the secured
    /// asset — this is the number that actually leaves the position.
    func testSendTransactionConvertsTheAmountToBaseUnits() {
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE()])
        let tx = Self.makeBuilder(amount: Decimal(string: "0.5")!).buildSendTransaction(vault: vault)
        XCTAssertEqual(tx.amountInRaw, 50_000_000)
    }

    /// A redemption is not a staking operation and carries no staking payload —
    /// `FunctionTransactionScreen`'s fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder()
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
