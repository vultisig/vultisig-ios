//
//  DecodedTransactionPresentation.swift
//  VultisigApp
//
//  Turning a decoded reading into the sentence a co-signer is shown.
//
//  ⚠️ **This is where base units become a human figure, and therefore where the
//  untrusted metadata comes back.** Decoding deliberately stops at raw units so
//  its result cannot be moved by `decimals`, which the chain never commits to.
//  Rendering has no such luxury: a person cannot read `150000000`, and the only
//  thing that can scale it is the payload's own `decimals`.
//
//  So the exposure is not removed by decoding, it is CONCENTRATED here — one
//  place, stated out loud, instead of spread through every screen. Two rules
//  keep that honest:
//
//  1. A quantity is only ever rendered against the transaction's own coin,
//     whose decimals are at least the ones the rest of the app already trusts
//     for this payload. An amount denominated in some other signed denom — a
//     receipt share, a Rujira contract denom — has no decimals we can look up,
//     so the verb is shown WITHOUT a figure rather than with a scaled guess.
//  2. A zero figure is never rendered. It is the defect this whole path exists
//     to remove, and a scaled zero is no more true than an unscaled one.
//

import BigInt
import Foundation

enum DecodedTransactionPresentation {

    /// The hero for a decoded transaction, or `nil` when nothing better than the
    /// screen's existing header can honestly be said.
    ///
    /// `nil` is the common answer and not a failure: an ordinary transfer, a
    /// swap, an approve and anything `.unknown` all keep exactly what they
    /// showed before. This speaks only where the generic send vocabulary is
    /// actively wrong.
    static func hero(for decoded: DecodedTransaction, coin: Coin) -> HeroContent? {
        guard let title = title(for: decoded.operation) else { return nil }

        switch decoded.amount {
        case .units(let raw, .transactionCoin):
            let amount = coin.decimal(for: raw)
            // A verb over a zero is the bug in better clothes.
            guard amount > 0 else { return .title(text: title, caption: nil) }
            return .send(
                title: title,
                coin: HeroCoinAmount(
                    // The asset's own precision, not the amount field's: chains
                    // settle in whole base units, so truncating there reproduces
                    // the payout rather than approximating it.
                    amount: amount.formatToDecimal(digits: coin.decimals),
                    ticker: coin.ticker,
                    logo: coin.logo
                )
            )

        case .fraction(let basisPoints, _):
            // ⚠️ The share caption says "of your staked <ASSET>", which is only
            // true of a STAKED position. A liquidity withdrawal's fraction is a
            // share of a two-sided POOL, and the asset it would name is the
            // transaction's coin rather than the pool — so `-:BTC.BTC:5000` read
            // "50% of your staked RUNE", which is false twice over. Until that
            // has copy of its own, the verb alone is what can be said.
            guard decoded.operation != .removeLiquidity else {
                return .title(text: title, caption: nil)
            }

            // A `tcy-:<bps>` memo commits to a SHARE of whatever is staked when
            // the chain executes it, so the share is the only exact thing there
            // is to say. Naming an amount would mean reading the position
            // off-chain first.
            return .title(
                text: title,
                caption: String(
                    format: "withdrawingShareOfStakedPosition".localized,
                    percentage(fromBasisPoints: basisPoints),
                    coin.ticker
                )
            )

        case .units(_, .denom):
            // Signed, exact, and unrenderable: nothing here knows how many
            // decimals a receipt denom carries, and inventing a scale for it
            // would restate the very problem decoding was changed to avoid.
            return .title(text: title, caption: nil)

        case .unstated:
            return .title(text: title, caption: nil)
        }
    }

    /// The hero for a payload, decoding it first.
    static func hero(for payload: KeysignPayload) -> HeroContent? {
        hero(for: SignedTransactionDecoder.decode(payload), coin: payload.coin)
    }

    /// The verb alone, for composing with a hero somebody else supplies.
    ///
    /// ⚠️ **This is what keeps decoding and simulation independent.** They
    /// answer different questions — a Blockaid simulation reports the balance
    /// changes a transaction produces, decoding reports which operation it is —
    /// and they were briefly made to compete for one hero slot, so a decoded
    /// verb silently displaced a simulation's figures. Handing the verb over as
    /// a TITLE lets the simulation keep the numbers it is better at while the
    /// decoding supplies the word it is better at.
    static func operationTitle(for payload: KeysignPayload) -> String? {
        title(for: SignedTransactionDecoder.decode(payload).operation)
    }

    /// The headline for an operation, or `nil` where the generic vocabulary is
    /// not actually wrong and the screen should keep what it had.
    ///
    /// Reuses the keys the initiator's Verify already renders rather than adding
    /// a second set saying the same thing — they are the same sentence about the
    /// same operation, and two sets would only let the screens drift apart.
    private static func title(for operation: DecodedOperation) -> String? {
        switch operation {
        case .stake: return "youreStaking".localized
        case .unstake: return "youreUnstaking".localized
        case .bond: return "youreBonding".localized
        case .unbond: return "youreUnbonding".localized
        case .delegate: return "youreDelegating".localized
        case .undelegate: return "youreUndelegating".localized
        case .redelegate: return "youreRedelegating".localized
        case .claimRewards: return "youreClaimingRewards".localized
        case .mint: return "youreMinting".localized
        case .redeem: return "youreRedeeming".localized
        case .addLiquidity: return "youreAddingLiquidity".localized
        case .removeLiquidity: return "youreRemovingLiquidity".localized

        // ⚠️ Everything below deliberately has no hero yet, and the reasons
        // differ. A transfer, a swap and an approve are already described
        // correctly by the screens. `.unknown` and `.contractCall` have nothing
        // true to add. The rest — rebond, leave, merge, secured assets, switch,
        // limit orders, vote, IBC — are recognised by the decoder but have no
        // copy in the eight shipping locales, and inventing English-only strings
        // for a screen people approve transactions on is worse than leaving them
        // as they are. Each is a translation away from working.
        case .transfer, .swap, .approve, .rebond, .leave, .merge, .unmerge,
             .ibcTransfer, .vote, .securedAssetDeposit, .securedAssetWithdraw,
             .switchChain, .limitOrderPlacement, .limitOrderCancel,
             .contractCall, .unknown:
            return nil
        }
    }

    /// Basis points as a percentage, without trailing noise: 10000 reads "100%",
    /// 5000 reads "50%", 5006 reads "50.06%".
    ///
    /// ⚠️ Formatted with `.percent` rather than by appending an ASCII `%`.
    /// Where the symbol sits, whether a space precedes it, and which symbol is
    /// used at all are locale rules — and gluing one on by hand also produces
    /// the wrong thing under bidirectional text. Feeding the formatter a
    /// fraction lets it apply those rules instead of this function guessing them.
    private static func percentage(fromBasisPoints basisPoints: Int) -> String {
        let fraction = Decimal(basisPoints) / 10_000
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = .current
        return formatter.string(from: fraction as NSDecimalNumber) ?? "\(basisPoints / 100)%"
    }
}
