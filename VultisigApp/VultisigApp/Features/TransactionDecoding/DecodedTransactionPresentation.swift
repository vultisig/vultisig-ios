//
//  DecodedTransactionPresentation.swift
//  VultisigApp
//
//  Converts provenance-aware readings into display content. This is the single
//  boundary where unsigned ticker, logo, and decimal metadata may enter.
//

import BigInt
import Foundation

enum DecodedTransactionPresentation {

    /// Recognized operations that intentionally produce no decoder hero.
    static let deliberatelySilent: [DecodedOperation: String] = [
        // These screens already provide a more specific presentation.
        .transfer: "the send screens already describe a transfer",
        .swap: "SwapVerifyScreen renders both sides, which a verb cannot improve on",
        .approve: "the approval screens name the spender and the allowance",

        // Nothing useful to add.
        .unknown: "nothing readable identified the transaction",
        .contractCall: "a contract call with no known shape behind it",
        .vote: "a vote moves no value; the verb alone would be the whole hero",
        // Naming this would hide its signed carrier charge.
        .removeLiquidity: "naming it would hide the carrier charge it signs"

        // New named operations require copy in every shipping locale.
    ]

    /// The localized verb, or `nil` for a deliberately silent operation.
    static func title(for operation: DecodedOperation) -> String? {
        localizationKey(for: operation)?.localized
    }

    /// Exposed so tests can validate keys against every shipping locale.
    static func localizationKey(for operation: DecodedOperation) -> String? {
        switch operation {
        case .stake: return "youreStaking"
        case .unstake: return "youreUnstaking"
        case .claimRewards: return "youreClaiming"
        case .bond: return "youreBonding"
        case .unbond: return "youreUnbonding"
        case .rebond: return "youreRebonding"
        case .leave: return "youreLeaving"
        case .securedAssetDeposit: return "youreDepositing"
        case .securedAssetWithdraw: return "youreWithdrawing"
        case .switchChain: return "youreSwitching"
        case .limitOrderPlacement: return "yourePlacingOrder"
        case .limitOrderCancel: return "youreCancellingOrder"
        case .delegate: return "youreDelegating"
        case .undelegate: return "youreUndelegating"
        case .redelegate: return "youreRedelegating"
        case .addLiquidity: return "youreAddingLiquidity"
        case .redeem: return "youreRedeeming"
        case .withdrawStake: return "youreWithdrawing"
        case .mint: return "youreMinting"
        case .merge: return "youreMerging"
        case .unmerge: return "youreUnmerging"
        case .ibcTransfer: return "youreBridging"

        // Exhaustive so new operations require an explicit vocabulary decision.
        case .transfer, .swap, .approve, .vote, .contractCall, .removeLiquidity, .unknown:
            return nil
        }
    }

    /// Builds a hero, using `coin` only for presentation metadata.
    static func hero(for decoded: DecodedTransaction, coin: Coin) -> HeroContent? {
        guard let title = title(for: decoded.operation) else { return nil }

        // Execution-set quantities state their signed scope immediately. A
        // later chain read may add an estimate, but never owns the verb/scope.
        if let projected = ProjectionCoordinator.hero(for: decoded, title: title) {
            return projected
        }

        switch decoded.amount {
        case .units(let raw, .transactionCoin):
            // A verb over a zero is the bug in better clothes.
            guard let amount = scaled(raw, decimals: coin.decimals), amount > 0 else {
                return .title(text: title, caption: nil)
            }
            return .send(
                title: title,
                // Use the asset's base-unit precision and trusted local rate key.
                coin: HeroCoinAmount(amount: amount, coin: coin)
            )

        case .units(let raw, .chainNative):
            // The chain-native unit is committed by the operation, so resolve
            // its display metadata from the chain rather than payload sidecars.
            guard let meta = TokensStore.nativeAsset(for: coin.chain),
                  let amount = scaled(raw, decimals: meta.decimals), amount > 0 else {
                return .title(text: title, caption: nil)
            }
            return .send(
                title: title,
                coin: HeroCoinAmount(amount: amount, coin: meta)
            )

        case .units(let raw, .denom(let denom)):
            // Cosmos denoms are case-sensitive; reject the helper's insensitive match.
            guard let meta = TokensStore.findTokenMeta(chain: coin.chain, contractAddress: denom),
                  meta.contractAddress == denom else {
                return .title(text: title, caption: nil)
            }
            guard let amount = scaled(raw, decimals: meta.decimals), amount > 0 else {
                return .title(text: title, caption: nil)
            }
            return .send(
                title: title,
                coin: HeroCoinAmount(
                    amount: amount.formatToDecimal(digits: meta.decimals),
                    ticker: meta.ticker,
                    logo: meta.logo
                )
            )

        case .accountFunding:
            // The reserve must be read live before this can be shown as stake.
            return .title(text: title, caption: nil)

        case .fraction:
            // Projection and localized scope arrive with fractional readers.
            return .title(text: title, caption: nil)

        case .unstated:
            return .title(text: title, caption: nil)
        }
    }

    /// Scales without the Double-backed `NumberFormatter` path. Values beyond
    /// `Decimal` precision are refused rather than rounded.
    private static func scaled(_ raw: BigInt, decimals: Int) -> Decimal? {
        let digits = raw.description
        guard digits.count <= 38, let value = Decimal(string: digits) else { return nil }
        return value / pow(Decimal(10), decimals)
    }

    /// Supplies a verb to richer presentation without replacing its figures.
    static func operationTitle(for payload: KeysignPayload) -> String? {
        title(for: SignedTransactionDecoder.decode(payload).operation)
    }

    /// Basis points as a localized percentage without trailing precision noise.
    static func percentage(fromBasisPoints basisPoints: Int) -> String {
        let fraction = Decimal(basisPoints) / 10_000
        return fraction.formatted(.percent.precision(.fractionLength(0...2)))
    }
}
