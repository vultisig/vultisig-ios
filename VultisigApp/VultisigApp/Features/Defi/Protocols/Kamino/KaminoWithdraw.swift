//
//  KaminoWithdraw.swift
//  VultisigApp
//

import BigInt
import Foundation

/// The user's share balance in one vault, split the way `/positions` reports it.
///
/// Shares, never tokens: the withdraw endpoint takes shares, the vault's
/// `minWithdrawAmount` is in shares, and the balance a full withdraw must send
/// is a share count. The token figure the form is denominated in is a projection
/// of these at the current rate, and it is derived — never the other way round.
struct KaminoSharePosition: Equatable {
    let staked: KaminoShareAmount
    let unstaked: KaminoShareAmount
    let total: KaminoShareAmount

    /// Parses one `/positions` element at the vault's pinned share scale.
    /// `nil` when any of the three values is not a plain decimal — a value that
    /// is present and unreadable is a failed read, not a zero balance.
    init?(response: KaminoUserPositionResponse, shareDecimals: Int) {
        guard let staked = KaminoShareAmount(decimalString: response.stakedShares, decimals: shareDecimals),
              let unstaked = KaminoShareAmount(decimalString: response.unstakedShares, decimals: shareDecimals),
              let total = KaminoShareAmount(decimalString: response.totalShares, decimals: shareDecimals)
        else { return nil }

        self.staked = staked
        self.unstaked = unstaked
        self.total = total
    }

    init(staked: KaminoShareAmount, unstaked: KaminoShareAmount, total: KaminoShareAmount) {
        self.staked = staked
        self.unstaked = unstaked
        self.total = total
    }

    /// Whether the three reported numbers can all be true at once.
    ///
    /// A response saying the user holds more of either kind of share than they
    /// hold in total is one whose figures cannot be spent as a balance — and
    /// spending a balance that is too large is precisely the mistake the API
    /// turns into `u64::MAX`.
    var isPlausible: Bool {
        staked.baseUnits >= 0
            && unstaked.baseUnits >= 0
            && staked.baseUnits <= total.baseUnits
            && unstaked.baseUnits <= total.baseUnits
    }

    /// Whether the whole position is unstaked shares and nothing else.
    ///
    /// This, rather than `staked == 0`, is what makes a withdraw of `unstaked`
    /// a withdraw of the *position*. A response whose total exceeds the two
    /// reported kinds has shares it has not accounted for, and an unaccounted
    /// share may well be a staked one — in which case spending only the
    /// unstaked remainder would present a partial exit as a complete one.
    ///
    /// Stated as `unstaked == total` rather than `staked + unstaked == total`
    /// on purpose. Both hold in the case that matters — an entirely unstaked
    /// position reports the same figure twice, so the two strings truncate
    /// identically at the vault's share scale — but the sum can disagree by a
    /// base unit purely from truncating two different strings, and that would
    /// refuse a real position over a last decimal place.
    var holdsOnlyUnstakedShares: Bool {
        unstaked.baseUnits == total.baseUnits
    }
}

/// What a withdraw from one vault may do right now.
///
/// The `farmStaked` case is the whole reason this type exists. Every deposit
/// into the launch vaults auto-stakes its shares into the vault's farm, and the
/// transaction that spends *staked* shares has never been observed — so the
/// validator has no template for it, and building one would mean asserting
/// against a guessed instruction layout. This enum makes that a named,
/// user-visible state instead of a refusal deep inside the pipeline.
enum KaminoWithdrawEligibility: Equatable {

    /// The observed path. The associated value is the exact unstaked share
    /// balance, and a full withdraw sends precisely this — never a number
    /// converted out of an asset amount.
    case withdrawable(KaminoShareAmount)

    /// Shares are staked in the vault's farm. Nothing is built.
    case farmStaked(KaminoShareAmount)

    /// The user holds no shares in this vault.
    case empty

    /// The position could not be read. Refused rather than treated as zero (a
    /// silent "nothing to withdraw" on a real position) or as whole (an amount
    /// the user does not have).
    case unreadable

    /// The share balance a withdraw may spend, or `nil` when none may be spent.
    var withdrawableShares: KaminoShareAmount? {
        guard case .withdrawable(let shares) = self else { return nil }
        return shares
    }

    /// Resolves the state from this vault's `/positions` entry.
    ///
    /// - Parameter response: the element for this vault, or `nil` when the vault
    ///   is absent from the response — which is a real "holds nothing" answer.
    static func resolve(
        response: KaminoUserPositionResponse?,
        shareDecimals: Int
    ) -> KaminoWithdrawEligibility {
        guard let response else { return .empty }
        guard let position = KaminoSharePosition(response: response, shareDecimals: shareDecimals),
              position.isPlausible
        else { return .unreadable }

        // Staked first, and unconditionally: a position that is even partly
        // staked cannot be fully withdrawn by the transaction shape this app
        // knows, and offering to spend only the unstaked remainder of a staked
        // position would quietly under-withdraw.
        guard position.staked.isZero else { return .farmStaked(position.staked) }
        // Then the shares the response did not account for. `staked == 0` alone
        // does not mean "nothing is staked" — it means nothing was *reported*
        // as staked, and a total larger than the parts is a position this app
        // cannot describe.
        guard position.holdsOnlyUnstakedShares else { return .unreadable }
        guard !position.unstaked.isZero else { return .empty }
        return .withdrawable(position.unstaked)
    }
}

/// Whether the vault can settle a withdraw out of the balance it holds liquid.
///
/// Not an error state. The measured liquid buffer is 0.36% of the Steakhouse
/// vault and 0.04% of the Allez vault, so a withdraw exceeding it is the common
/// case rather than an edge one, and it is rendered as an ordinary fact about
/// the vault.
///
/// What happens on chain when the buffer is short has not been observed, so
/// nothing here claims to know: this is a comparison of two published numbers,
/// not a decode of a program error.
enum KaminoWithdrawLiquidity: Equatable {
    case instant
    case delayed(available: KaminoTokenAmount)

    var availableTokens: KaminoTokenAmount? {
        guard case .delayed(let available) = self else { return nil }
        return available
    }

    static func resolve(
        requested: KaminoTokenAmount,
        available: KaminoTokenAmount?
    ) -> KaminoWithdrawLiquidity {
        guard let available, requested.baseUnits > available.baseUnits else { return .instant }
        return .delayed(available: available)
    }
}

/// The conversions a withdraw form performs, in one place so the form's gate,
/// its maximum and the amount it actually sends can never disagree.
enum KaminoWithdrawMath {

    /// The most the held shares are worth in the underlying asset, truncated.
    /// This is the form's maximum, and the number a 100% button writes.
    static func maximumTokens(
        shares: KaminoShareAmount,
        tokensPerShare rate: KaminoRate,
        tokenDecimals: Int
    ) -> KaminoTokenAmount? {
        shares.tokenValue(tokensPerShare: rate, tokenDecimals: tokenDecimals)
    }

    /// The vault's share-denominated minimum expressed in the asset, rounded up
    /// so that anything at or above it converts back to at least the minimum.
    static func minimumTokens(
        minimumShares: KaminoShareAmount,
        tokensPerShare rate: KaminoRate,
        tokenDecimals: Int
    ) -> KaminoTokenAmount? {
        minimumShares.tokenValueRoundedUp(tokensPerShare: rate, tokenDecimals: tokenDecimals)
    }

    /// The shares a withdraw of `tokens` burns, or `nil` when no withdraw of
    /// that size can be sized safely.
    ///
    /// **This function is the fund-safety boundary of the whole flow.** The API
    /// validates nothing: a withdraw naming more shares than the user holds is
    /// silently rewritten to `u64::MAX`, which means *withdraw everything*. So
    /// an over-request by a single base unit turns a partial withdraw into a
    /// full exit.
    ///
    /// Three branches, and each one is a different answer to that:
    ///
    /// - **Above the maximum**: refused. Nothing here may interpret "more than
    ///   the position" as "the position" — a mistyped digit would then be a full
    ///   exit the user never asked for, and the button that reaches this is
    ///   tappable whatever the form's validators think (`FormScreen` disables
    ///   Continue only on its explicit flag, not on `validForm`). Refusing is
    ///   also the only answer that stays true if the balance moved since it was
    ///   read.
    /// - **Exactly the maximum**: a full withdraw, and it sends `held` — the
    ///   exact balance that was read — rather than a number converted out of the
    ///   asset amount. Round-tripping the maximum through tokens and back is
    ///   precisely how the extra base unit would be introduced.
    /// - **Below it**: the conversion truncates. Both `maximumTokens` and this
    ///   division round down, so `tokens < maximumTokens` implies the result is
    ///   `≤ held` — the partial branch cannot even reach the balance.
    ///
    /// Which leaves no arithmetic anywhere that produces a request larger than
    /// the user's own balance.
    static func shares(
        forTokens tokens: KaminoTokenAmount,
        held: KaminoShareAmount,
        maximumTokens: KaminoTokenAmount,
        tokensPerShare rate: KaminoRate,
        shareDecimals: Int
    ) -> KaminoShareAmount? {
        guard tokens.baseUnits > 0, held.baseUnits > 0 else { return nil }
        guard tokens.baseUnits <= maximumTokens.baseUnits else { return nil }
        guard tokens.baseUnits < maximumTokens.baseUnits else { return held }
        return tokens.shareAmount(tokensPerShare: rate, shareDecimals: shareDecimals)
    }
}

/// Rejects an entered asset amount whose share equivalent is below the vault's
/// `minWithdrawAmount`.
///
/// The minimum is in SHARE base units, so it can only be judged **after** the
/// conversion. Comparing the typed token amount against it directly would be
/// wrong by the whole share rate — on the SOL vault that rate is 0.0010749
/// tokens per share, so the naive comparison is off by a factor of about 930.
///
/// It converts through `KaminoWithdrawMath.shares`, which is the same function
/// that sizes the transaction, so the gate and the request can never disagree.
struct KaminoMinWithdrawValidator: FormFieldValidator {
    let held: KaminoShareAmount
    let maximumTokens: KaminoTokenAmount
    let minimumShares: KaminoShareAmount
    let tokensPerShare: KaminoRate
    let tokenDecimals: Int
    let shareDecimals: Int
    let errorMessage: String

    func validate(value: String) throws {
        guard value.isNotEmpty else { return }
        // A malformed or zero amount is the other validators' error to report.
        guard let tokens = KaminoAmountInput.tokenAmount(value, decimals: tokenDecimals),
              tokens.baseUnits > 0
        else { return }
        // So is an amount above the position. `AmountBalanceValidator` names
        // that one properly; reporting it as a minimum violation would be wrong
        // twice over.
        guard tokens.baseUnits <= maximumTokens.baseUnits else { return }

        guard let shares = KaminoWithdrawMath.shares(
            forTokens: tokens,
            held: held,
            maximumTokens: maximumTokens,
            tokensPerShare: tokensPerShare,
            shareDecimals: shareDecimals
        ), shares.baseUnits >= minimumShares.baseUnits else {
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
