//
//  LimitSwapCancelMemoBuilderTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class LimitSwapCancelMemoBuilderTests: XCTestCase {

    // MARK: - Memo vectors

    func testBuildsCancelMemoForRuneSource() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(100_000_000),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(15_979_057_441)
            )
        )
        XCTAssertEqual(memo, "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0")
    }

    /// ⚠️ Regression for the 2026-07-21 mainnet rehearsal: the cancel was
    /// REJECTED (`could not find matching limit swap`) because the target asset
    /// carried the PLACEMENT memo's 6-character contract suffix. That form is
    /// resolved by `fuzzyAssetMatch` when an order is placed, but `m=<` is the
    /// one inbound memo type that skips fuzzy matching, so the abbreviation
    /// keyed a bucket the order was never indexed under.
    ///
    /// The byte-exact memo the rejected one should have been.
    func testBuildsCancelMemoWithTheFullContractForAnEvmTarget() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(370_939_666),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(167_889_485)
            )
        )

        XCTAssertEqual(
            memo,
            "m=<:370939666THOR.RUNE:167889485ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48:0"
        )
        XCTAssertEqual(memo.utf8.count, 85)
    }

    /// The builder REFUSES the abbreviated spelling rather than trusting callers
    /// to pass the long one — on either leg. An ERC20-sourced order has the
    /// identical bug and would fail the identical way.
    func testRejectsAnAbbreviatedContractAssetOnEitherLeg() {
        let abbreviatedTarget = LimitOrderCancelInputs(
            sourceAsset: "THOR.RUNE",
            sourceAmount1e8: BigInt(370_939_666),
            targetAsset: "ETH.USDC-06EB48",
            tradeTarget: BigInt(167_889_485)
        )
        XCTAssertThrowsError(try buildCancelLimitSwapMemo(abbreviatedTarget)) { error in
            XCTAssertEqual(error as? LimitSwapCancelMemoError, .abbreviatedAsset)
        }

        let abbreviatedSource = LimitOrderCancelInputs(
            sourceAsset: "ETH.USDC-06EB48",
            sourceAmount1e8: BigInt(370_939_666),
            targetAsset: "THOR.RUNE",
            tradeTarget: BigInt(167_889_485)
        )
        XCTAssertThrowsError(try buildCancelLimitSwapMemo(abbreviatedSource)) { error in
            XCTAssertEqual(error as? LimitSwapCancelMemoError, .abbreviatedAsset)
        }
    }

    /// The abbreviation detector has to leave every legitimate spelling alone —
    /// a false positive here makes a perfectly cancellable order uncancellable.
    func testAbbreviationDetectionAcceptsEveryFullSpelling() {
        for asset in [
            "THOR.RUNE", "BTC.BTC", "ETH.ETH", "GAIA.ATOM", "THOR.TCY",
            "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            "ETH~USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            // ⚠️ A SECURED asset spells the whole identifier with `-`, so a
            // secured NATIVE denom is chain + ticker and nothing else. Reading
            // the tail after the last `-` would call these truncated and make
            // every secured-native order permanently uncancellable.
            "btc-btc", "eth-eth", "BTC-BTC", "doge-doge"
        ] {
            XCTAssertFalse(thorchainMemoAssetIsAbbreviated(asset), asset)
        }
        for asset in ["ETH.USDC-06EB48", "BSC.TWT-508003", "ETH.USDC-", "eth-usdc-06eb48"] {
            XCTAssertTrue(thorchainMemoAssetIsAbbreviated(asset), asset)
        }
    }

    /// A secured-asset source keeps its bare `-` denom. Normalizing it to the
    /// layer-1 form would make THORNode's `Asset.GetChain()` report the L1 chain,
    /// and `ValidateBasic` would then reject a cancel sent from a THOR address.
    func testBuildsCancelMemoForSecuredAssetSourceKeepingTheSecuredDenom() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                sourceAmount1e8: BigInt(250_000_000),
                targetAsset: "THOR.RUNE",
                tradeTarget: BigInt(1_234_567)
            )
        )
        XCTAssertEqual(
            memo,
            "m=<:250000000eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48:1234567THOR.RUNE:0"
        )
    }

    /// The coin amounts go through THORNode's `cosmos.ParseCoins` /
    /// `common.ParseCoin`, which understand plain integers only — unlike the
    /// PLACEMENT memo's LIM, which is parsed with scientific-notation support.
    /// A trailing-zero-heavy amount must therefore stay expanded.
    func testAmountsAreNeverScientificNotationCompressed() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(544_000_000),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(510_000_000)
            )
        )
        XCTAssertEqual(memo, "m=<:544000000THOR.RUNE:510000000BTC.BTC:0")
        XCTAssertFalse(memo.contains("e"), "amounts must not be compressed to <mantissa>e<exp>")
    }

    func testModifyMemoIsRecognizedByItsOwnPredicateAndNotThePlacementOne() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(1),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(1)
            )
        )
        XCTAssertTrue(isModifyLimitSwapMemo(memo))
        XCTAssertFalse(isLimitSwapMemo(memo))
        XCTAssertFalse(isModifyLimitSwapMemo("=<:BTC.BTC:addr:1e8/14400/0::0"))
        XCTAssertFalse(isModifyLimitSwapMemo(nil))
    }

    func testThirdFieldIsAlwaysZeroSoTheMemoCancelsRatherThanModifies() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(7),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(9)
            )
        )
        XCTAssertEqual(memo.split(separator: ":").last.map(String.init), "0")
    }

    func testRejectsNonPositiveAmounts() {
        let zeroSource = LimitOrderCancelInputs(
            sourceAsset: "THOR.RUNE",
            sourceAmount1e8: BigInt(0),
            targetAsset: "BTC.BTC",
            tradeTarget: BigInt(1)
        )
        XCTAssertThrowsError(try buildCancelLimitSwapMemo(zeroSource)) { error in
            XCTAssertEqual(error as? LimitSwapCancelMemoError, .nonPositiveAmount)
        }

        let zeroTarget = LimitOrderCancelInputs(
            sourceAsset: "THOR.RUNE",
            sourceAmount1e8: BigInt(1),
            targetAsset: "BTC.BTC",
            tradeTarget: BigInt(0)
        )
        XCTAssertThrowsError(try buildCancelLimitSwapMemo(zeroTarget)) { error in
            XCTAssertEqual(error as? LimitSwapCancelMemoError, .nonPositiveAmount)
        }
    }

    func testRejectsEmptyAssets() {
        let inputs = LimitOrderCancelInputs(
            sourceAsset: "",
            sourceAmount1e8: BigInt(1),
            targetAsset: "BTC.BTC",
            tradeTarget: BigInt(1)
        )
        XCTAssertThrowsError(try buildCancelLimitSwapMemo(inputs)) { error in
            XCTAssertEqual(error as? LimitSwapCancelMemoError, .emptyAsset)
        }
    }

    // MARK: - Eligibility

    func testRestingThorchainSourcedOrderIsCancellable() {
        let details = makeDetails()
        guard case let .cancellable(inputs) = limitOrderCancelEligibility(details) else {
            return XCTFail("expected cancellable")
        }
        XCTAssertEqual(inputs.sourceAmount1e8, BigInt(100_000_000))
        XCTAssertEqual(inputs.tradeTarget, BigInt(15_979_057_441))
        XCTAssertEqual(inputs.sourceAsset, "THOR.RUNE")
    }

    /// A secured-asset source is THORChain-placed even though its denom carries
    /// no `THOR.` prefix — which is exactly why the chain is recorded separately
    /// rather than inferred from `sourceAsset`.
    func testSecuredAssetSourceIsCancellable() {
        let details = makeDetails(sourceAsset: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertTrue(limitOrderCancelEligibility(details).isCancellable)
    }

    /// A BTC-funded order is cancellable from BTC — THORNode dispatches `m=<`
    /// from the Bifrost observed-tx path as well as from a native deposit.
    func testL1SourcedOrderOnARoutableChainIsCancellable() {
        let details = makeDetails(sourceChainRawValue: Chain.bitcoin.rawValue)
        XCTAssertTrue(limitOrderCancelEligibility(details).isCancellable)
    }

    func testUnroutableSourceChainIsNotCancellable() {
        let details = makeDetails(sourceChainRawValue: Chain.solana.rawValue)
        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .unsupportedSourceChain)
    }

    func testOrderWithNoRecordedSourceChainIsNotCancellable() {
        let details = makeDetails(sourceChainRawValue: nil)
        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .missingSignedData)
    }

    func testOrderWithUnrecognizedSourceChainIsNotCancellable() {
        let details = makeDetails(sourceChainRawValue: "notAChain")
        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .missingSignedData)
    }

    func testOrderPlacedBeforeAmountsWereRecordedIsNotCancellable() {
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(sourceAmount1e8: nil)).blocker,
            .missingSignedData
        )
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(tradeTarget: nil)).blocker,
            .missingSignedData
        )
    }

    func testUnparseableOrNonPositiveAmountsAreNotCancellable() {
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(sourceAmount1e8: "not-a-number")).blocker,
            .missingSignedData
        )
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(tradeTarget: "0")).blocker,
            .missingSignedData
        )
    }

    func testTerminalOrderIsNotCancellable() {
        for status in [LimitOrderStatus.filled, .refunded, .expired, .cancelled] {
            XCTAssertEqual(
                limitOrderCancelEligibility(makeDetails(status: status)).blocker,
                .terminal,
                "\(status) should block cancelling"
            )
        }
    }

    // MARK: - Placement/queue cross-check

    func testDepositDisagreementWithTheQueueBlocksCancelling() {
        let details = makeDetails(depositAmount: "99999999")
        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .signedDataDisagreesWithChain)
    }

    func testTradeTargetDisagreementWithTheQueueBlocksCancelling() {
        let details = makeDetails(observedTradeTarget: "12345")
        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .signedDataDisagreesWithChain)
    }

    func testAgreementWithTheQueueKeepsTheOrderCancellable() {
        let details = makeDetails(
            depositAmount: "100000000",
            observedTradeTarget: "15979057441"
        )
        XCTAssertTrue(limitOrderCancelEligibility(details).isCancellable)
    }

    /// An order placed seconds ago has not been polled yet. Absence of an
    /// observation is not a disagreement — refusing to cancel until the first
    /// poll lands would be a worse failure than the one the check prevents.
    func testUnobservedOrderIsStillCancellable() {
        let details = makeDetails(depositAmount: nil, observedTradeTarget: nil)
        XCTAssertTrue(limitOrderCancelEligibility(details).isCancellable)
    }

    /// "Absent" and "present but unparseable" are different claims. The second
    /// means the wire carried something this code does not model, so the
    /// amounts went unverified — that blocks, exactly as a mismatch does.
    func testUnparseableObservationBlocksRatherThanCountingAsUnobserved() {
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(depositAmount: "not-a-number")).blocker,
            .signedDataDisagreesWithChain
        )
        XCTAssertEqual(
            limitOrderCancelEligibility(makeDetails(observedTradeTarget: "")).blocker,
            .signedDataDisagreesWithChain
        )
    }

    // MARK: - Asset resolution

    /// The rescue path for the order the failed rehearsal left resting: its
    /// stored target asset is the lossy `ETH.USDC-06EB48` and it predates
    /// `targetAssetFull`, so the queue's own report is the only source of the
    /// full contract — and it is authoritative, being the string THORChain
    /// built the order's index entry from.
    func testAQueueObservedAssetSuppliesTheFullContractForALegacyOrder() throws {
        let details = makeDetails(
            targetAsset: "ETH.USDC-06EB48",
            sourceChainRawValue: Chain.thorChain.rawValue,
            observedTargetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
        )

        guard case let .cancellable(inputs) = limitOrderCancelEligibility(details) else {
            return XCTFail("expected cancellable")
        }
        XCTAssertEqual(inputs.targetAsset, "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
        XCTAssertFalse(try buildCancelLimitSwapMemo(inputs).contains("06EB48:"))
    }

    /// An order placed after this change carries the full form itself, so it is
    /// cancellable in the window before the first queue poll lands.
    func testTheSignedFullFormIsUsedBeforeTheQueueHasReported() throws {
        let details = makeDetails(
            targetAsset: "ETH.USDC-06EB48",
            targetAssetFull: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
        )

        guard case let .cancellable(inputs) = limitOrderCancelEligibility(details) else {
            return XCTFail("expected cancellable")
        }
        XCTAssertEqual(inputs.targetAsset, "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
    }

    /// ⚠️ The whole point: with only the truncated spelling available, there is
    /// nothing safe to sign. Blocked — never the 6-character form, which is
    /// accepted by the chain, costs a fee and cancels nothing.
    func testAnAbbreviatedAssetWithNoFullFormAnywhereBlocks() {
        let details = makeDetails(targetAsset: "ETH.USDC-06EB48")

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .missingSignedData)
    }

    /// An ERC20 SOURCE has the identical bug, and blocks the identical way.
    func testAnAbbreviatedSourceAssetWithNoFullFormBlocks() {
        let details = makeDetails(
            sourceAsset: "ETH.USDC-06EB48",
            sourceChainRawValue: Chain.ethereum.rawValue
        )

        XCTAssertEqual(limitOrderCancelEligibility(details).blocker, .missingSignedData)
    }

    /// A native leg carries no token identifier to truncate, so the stored
    /// placement spelling IS the full spelling. Orders placed before any of this
    /// existed stay cancellable whenever both legs are native.
    func testNativeLegsStayCancellableWithNoRecordedFullForm() throws {
        let details = makeDetails(sourceAsset: "THOR.RUNE", targetAsset: "BTC.BTC")

        guard case let .cancellable(inputs) = limitOrderCancelEligibility(details) else {
            return XCTFail("expected cancellable")
        }
        XCTAssertEqual(try buildCancelLimitSwapMemo(inputs), "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0")
    }

    /// A secured denom is already the full on-chain identifier, so it needs no
    /// rescue — and must not be normalized on the way through.
    func testASecuredDenomIsAcceptedVerbatimWithoutAFullForm() throws {
        for denom in [
            "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            // A secured NATIVE asset carries no contract at all. Its short tail
            // is the ticker, not a truncation.
            "btc-btc"
        ] {
            let details = makeDetails(sourceAsset: denom)

            guard case let .cancellable(inputs) = limitOrderCancelEligibility(details) else {
                return XCTFail("expected \(denom) to be cancellable")
            }
            XCTAssertEqual(inputs.sourceAsset, denom)
        }
    }

    // MARK: - Duplicate detection

    func testDuplicatesAreDetectedByRatioNotByEqualAmounts() {
        // Twice the deposit at twice the target is the SAME price, so THORChain
        // files both under one ratio bucket and a cancel cannot tell them apart.
        let target = makeDetails(id: "a", sourceAmount1e8: "100000000", tradeTarget: "200000000")
        let sameRatio = makeDetails(id: "b", sourceAmount1e8: "200000000", tradeTarget: "400000000")
        let otherRatio = makeDetails(id: "c", sourceAmount1e8: "100000000", tradeTarget: "300000000")

        let duplicates = duplicateRestingLimitOrders(of: target, among: [target, sameRatio, otherRatio])
        XCTAssertEqual(duplicates.map(\.id), ["b"])
    }

    func testDuplicatesExcludeDifferentPairsAndUncancellableOrders() {
        let target = makeDetails(id: "a")
        let otherPair = makeDetails(id: "b", targetAsset: "ETH.ETH")
        let terminal = makeDetails(id: "c", status: .filled)
        let unroutable = makeDetails(id: "d", sourceChainRawValue: Chain.solana.rawValue)

        let duplicates = duplicateRestingLimitOrders(of: target, among: [target, otherPair, terminal, unroutable])
        XCTAssertTrue(duplicates.isEmpty)
    }

    func testDuplicatesAreOldestFirstBecauseTheOldestIsTheOneThatCloses() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let target = makeDetails(id: "a", createdAt: base.addingTimeInterval(300))
        let newer = makeDetails(id: "b", createdAt: base.addingTimeInterval(200))
        let oldest = makeDetails(id: "c", createdAt: base)

        let duplicates = duplicateRestingLimitOrders(of: target, among: [target, newer, oldest])
        XCTAssertEqual(duplicates.map(\.id), ["c", "b"])
    }

    func testAnUncancellableOrderReportsNoDuplicates() {
        let target = makeDetails(id: "a", sourceChainRawValue: Chain.solana.rawValue)
        let peer = makeDetails(id: "b")
        XCTAssertTrue(duplicateRestingLimitOrders(of: target, among: [target, peer]).isEmpty)
    }

    // MARK: - Bucket key

    /// Mirrors THORNode's `rewriteRatio`: short ratios are left-zero-padded to 18
    /// characters, long ones are truncated from the right.
    func testBucketKeyPadsShortRatiosToEighteenCharacters() {
        let key = thorchainLimitOrderBucketKey(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(1),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(1)
            )
        )
        // 1 * 1e8 / 1 = 100000000 → padded to 18 chars.
        XCTAssertEqual(key, "THOR.RUNE>BTC.BTC/000000000100000000/")
    }

    /// THORNode keys on LAYER-1 assets, so a secured/trade/synth representation
    /// and the plain L1 asset share a bucket on-chain. Comparing memo strings
    /// verbatim would miss exactly the collision the warning exists for.
    func testBucketKeyNormalizesSecuredTradeAndSynthAssetsToLayerOne() {
        func key(source: String, target: String) -> String {
            thorchainLimitOrderBucketKey(
                LimitOrderCancelInputs(
                    sourceAsset: source,
                    sourceAmount1e8: BigInt(1),
                    targetAsset: target,
                    tradeTarget: BigInt(1)
                )
            )
        }
        let layer1 = key(source: "ETH.USDC-0XA0B", target: "BTC.BTC")
        XCTAssertEqual(key(source: "eth-usdc-0xa0b", target: "BTC.BTC"), layer1, "secured")
        XCTAssertEqual(key(source: "ETH~USDC-0XA0B", target: "BTC.BTC"), layer1, "trade")
        XCTAssertEqual(key(source: "ETH/USDC-0XA0B", target: "BTC.BTC"), layer1, "synth")
        XCTAssertEqual(key(source: "ETH.USDC-0XA0B", target: "BTC~BTC"), layer1, "trade target")
    }

    /// A contract-suffixed L1 asset already contains `-`, but AFTER its `.`.
    /// Rewriting that would corrupt an asset that was already layer-1.
    func testLayerOneNormalizationLeavesAContractSuffixedAssetAlone() {
        XCTAssertEqual(thorchainLayer1MemoAsset("ETH.USDC-0XA0B"), "ETH.USDC-0XA0B")
        XCTAssertEqual(thorchainLayer1MemoAsset("THOR.RUNE"), "THOR.RUNE")
        XCTAssertEqual(thorchainLayer1MemoAsset("BTC.BTC"), "BTC.BTC")
    }

    func testBucketKeyTruncatesOverlongRatios() {
        // 1e30 * 1e8 / 1 is 39 digits; THORNode keeps only the first 18.
        let key = thorchainLimitOrderBucketKey(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(10).power(30),
                targetAsset: "BTC.BTC",
                tradeTarget: BigInt(1)
            )
        )
        let ratio = key.split(separator: "/")[1]
        XCTAssertEqual(ratio.count, 18)
        XCTAssertEqual(String(ratio), "100000000000000000")
    }

    // MARK: - Helpers

    private func makeDetails(
        id: String = "order-1",
        sourceAsset: String = "THOR.RUNE",
        targetAsset: String = "BTC.BTC",
        createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
        status: LimitOrderStatus = .pending,
        depositAmount: String? = nil,
        sourceAmount1e8: String? = "100000000",
        tradeTarget: String? = "15979057441",
        observedTradeTarget: String? = nil,
        sourceChainRawValue: String? = Chain.thorChain.rawValue,
        sourceAssetFull: String? = nil,
        targetAssetFull: String? = nil,
        observedSourceAsset: String? = nil,
        observedTargetAsset: String? = nil
    ) -> LimitOrderDetails {
        LimitOrderDetails(
            id: id,
            inboundTxHash: "HASH-\(id)",
            sourceAsset: sourceAsset,
            targetAsset: targetAsset,
            targetPrice: 1,
            expiryBlocks: 14_400,
            createdAt: createdAt,
            status: status,
            minOutputOverride: nil,
            fill: LimitOrderFill(
                depositAmount: depositAmount,
                filledInAmount: nil,
                filledOutAmount: nil
            ),
            expiry: nil,
            sourceAmount1e8: sourceAmount1e8,
            tradeTarget: tradeTarget,
            observedTradeTarget: observedTradeTarget,
            sourceAssetFull: sourceAssetFull,
            targetAssetFull: targetAssetFull,
            observedSourceAsset: observedSourceAsset,
            observedTargetAsset: observedTargetAsset,
            sourceChainRawValue: sourceChainRawValue
        )
    }
}
