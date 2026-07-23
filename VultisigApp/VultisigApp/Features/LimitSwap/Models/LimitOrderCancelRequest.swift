//
//  LimitOrderCancelRequest.swift
//  VultisigApp
//

import Foundation

/// Everything the cancel confirmation screen and its transaction builder need,
/// resolved BEFORE navigation.
///
/// The memo is carried rather than rebuilt downstream: it is derived from the
/// exact integers recorded at signing, and `limitOrderCancelEligibility` has
/// already decided this order may be cancelled at all. Rebuilding it on the
/// other side of a navigation boundary would let the check and the signed bytes
/// drift apart — and a cancel memo that addresses the wrong bucket fails
/// silently.
///
/// `Hashable` so it can ride inside `FunctionTransactionType` through a
/// navigation `Route`.
struct LimitOrderCancelRequest: Hashable, Sendable {
    /// Identifies the `LimitOrder` row to mark cancelled once the cancel is
    /// broadcast.
    let orderId: String
    /// The order's on-chain identity, shown for reference.
    let inboundTxHash: String
    /// The `m=<` memo, already built and validated.
    let memo: String
    /// DISPLAY ONLY — the order's assets in their placement spelling, which
    /// abbreviates an EVM contract to 6 characters and is what the rest of the
    /// app shows. The assets the memo above actually carries are spelled in
    /// full; they are not the same string and these must never be used to
    /// rebuild it.
    let sourceAsset: String
    let targetAsset: String
    /// `Chain.rawValue` the order was funded from — decides HOW the cancel is
    /// sent. THORChain-sourced orders cancel via a `MsgDeposit` from the vault's
    /// THOR address; every other chain cancels by sending the same memo from
    /// that chain, which THORNode observes through Bifrost.
    let sourceChainRawValue: String
    /// Other RESTING orders that share this one's THORChain bucket.
    ///
    /// Non-zero means the cancel may close a different order than the one the
    /// user tapped: THORChain addresses orders by (assets, ratio) + sender and
    /// takes the FIRST match, never by tx hash. The confirmation warns rather
    /// than blocks — blocking would strand the user with no way out.
    let duplicateRestingOrderCount: Int
    /// What the user must be shown before signing, resolved after the tap.
    ///
    /// `nil` on the request the detail sheet builds — the dust and the balance
    /// verdict need network calls that happen on the way to Verify. Filled in by
    /// `LimitOrderCancelPreparer`, which is the only thing that should write it.
    let disclosures: LimitOrderCancelDisclosures?

    init(
        orderId: String,
        inboundTxHash: String,
        memo: String,
        sourceAsset: String,
        targetAsset: String,
        sourceChainRawValue: String,
        duplicateRestingOrderCount: Int,
        disclosures: LimitOrderCancelDisclosures? = nil
    ) {
        self.orderId = orderId
        self.inboundTxHash = inboundTxHash
        self.memo = memo
        self.sourceAsset = sourceAsset
        self.targetAsset = targetAsset
        self.sourceChainRawValue = sourceChainRawValue
        self.duplicateRestingOrderCount = duplicateRestingOrderCount
        self.disclosures = disclosures
    }

    func with(disclosures: LimitOrderCancelDisclosures) -> LimitOrderCancelRequest {
        LimitOrderCancelRequest(
            orderId: orderId,
            inboundTxHash: inboundTxHash,
            memo: memo,
            sourceAsset: sourceAsset,
            targetAsset: targetAsset,
            sourceChainRawValue: sourceChainRawValue,
            duplicateRestingOrderCount: duplicateRestingOrderCount,
            disclosures: disclosures
        )
    }
}

/// Everything a user has to be told before signing a cancel.
///
/// These used to be an intermediate confirmation screen. A cancel is deep-linked
/// from the order's detail sheet with its assets, amounts and memo already
/// fixed, so that screen had no editable field and nothing to decide — the same
/// shape as the Solana unstake/withdraw rows, which build their transaction and
/// push straight to Verify. What it SAID has not gone anywhere; it rides here
/// onto Verify, where it sits directly above the signing button rather than one
/// screen before it.
struct LimitOrderCancelDisclosures: Hashable, Sendable {
    /// The dust the cancel has to attach, formatted for display, or `nil` on the
    /// THORChain route which attaches nothing.
    ///
    /// ⚠️ Non-refundable. Bifrost drops a zero-value transaction before it ever
    /// becomes an observed tx, so an L1 cancel must send something — and
    /// THORNode `donateToPool`s whatever arrives. On DOGE that is two whole
    /// coins. It must be stated with its exact amount before the user signs; a
    /// generic "network fees apply" would be actively misleading.
    let donatedAmount: String?
    /// The shared send validation's objection, already localized, when the vault
    /// cannot cover the dust plus the real chain fee. `nil` on the THORChain
    /// route, which prices only the deposit gas — see `canAffordCancel`.
    let balanceObjection: String?
    /// Whether the vault can pay for the cancel at all. `false` blocks signing
    /// and shows the insufficient-fee notice, exactly as the deleted screen's
    /// disabled Continue button did.
    let canAffordCancel: Bool
}
