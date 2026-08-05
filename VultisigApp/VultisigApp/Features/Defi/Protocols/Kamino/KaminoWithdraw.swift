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
    /// The most a withdraw may name — see the property's own note for why it is
    /// not simply `total`.
    let spendable: KaminoShareAmount

    /// Parses one `/positions` element at the vault's pinned share scale.
    /// `nil` when any of the three values is not a plain decimal — a value that
    /// is present and unreadable is a failed read, not a zero balance.
    ///
    /// Every value is TRUNCATED to the share mint's own decimals on the way in.
    /// The endpoint reports up to 14 decimal places for a 6-decimal mint, and
    /// the extra digits are not a balance anyone can spend: handing the reported
    /// string straight back as an amount asks for more than the position holds,
    /// which the API rewrites to its withdraw-everything sentinel.
    init?(response: KaminoUserPositionResponse, shareDecimals: Int) {
        guard let staked = KaminoShareAmount(decimalString: response.stakedShares, decimals: shareDecimals),
              let unstaked = KaminoShareAmount(decimalString: response.unstakedShares, decimals: shareDecimals),
              let total = KaminoShareAmount(decimalString: response.totalShares, decimals: shareDecimals),
              let spendable = Self.spendable(totalShares: response.totalShares, shareDecimals: shareDecimals)
        else { return nil }

        self.staked = staked
        self.unstaked = unstaked
        self.total = total
        self.spendable = spendable
        self.accountsForItsTotal = KaminoRate.sum(response.stakedShares, response.unstakedShares)
            .map { KaminoRate.isEqual($0, response.totalShares) } ?? false
    }

    init(staked: KaminoShareAmount, unstaked: KaminoShareAmount, total: KaminoShareAmount) {
        self.staked = staked
        self.unstaked = unstaked
        self.total = total
        self.spendable = Self.spendable(total: total)
        // Already at one scale, so the sum is exact here by construction.
        self.accountsForItsTotal = staked.baseUnits + unstaked.baseUnits == total.baseUnits
    }

    /// The largest share amount `POST /ktx/kvault/withdraw` will size as a share
    /// count rather than rewriting to `u64::MAX` — its *withdraw everything*
    /// sentinel.
    ///
    /// The sentinel fires at greater-than-**or-equal-to** the spendable balance,
    /// not merely above it. That was measured, not assumed, and on wallets where
    /// the balance is an exact `u64` in a token account, so there is no rounding
    /// anywhere in the comparison: requests of `3137.14326`, `71.999441` and
    /// `1683.002283` against balances of exactly those figures each came back as
    /// the sentinel, and each passed through as an ordinary share count one base
    /// unit below. So "the whole balance" is not a request this API accepts, and
    /// the maximum has to be the largest amount strictly beneath it.
    ///
    /// Truncating the reported string is necessary and NOT sufficient. It gives
    /// a value strictly below the balance only when there were digits past the
    /// mint's scale to throw away; when the balance is exactly representable the
    /// truncation is the balance, and asking for it is asking for everything. So
    /// the exact case gives up one base unit — `10^-6` of a share, which is
    /// worth about a ten-thousandth of a cent on the launch vaults — and the
    /// inexact case does not have to.
    ///
    /// Refusing the sentinel is the point of the whole withdraw guard, so it is
    /// never accepted here to make a 100% withdraw work. The dust is the price
    /// of the sentinel being indistinguishable, in the bytes, from an amount the
    /// user never asked for.
    private static func spendable(totalShares: String, shareDecimals: Int) -> KaminoShareAmount? {
        guard let rate = KaminoRate(apiString: totalShares),
              let scaled = KaminoAmountMath.scaleReportingExactness(rate: rate, toDecimals: shareDecimals)
        else { return nil }
        let baseUnits = scaled.isExact ? scaled.baseUnits - 1 : scaled.baseUnits
        return KaminoShareAmount(baseUnits: max(baseUnits, 0), decimals: shareDecimals)
    }

    /// The same rule for a position built from already-scaled amounts, where the
    /// total is exact by construction.
    private static func spendable(total: KaminoShareAmount) -> KaminoShareAmount {
        KaminoShareAmount(baseUnits: max(total.baseUnits - 1, 0), decimals: total.decimals)
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

    /// Whether the two reported parts add up to the reported total.
    ///
    /// A response whose total exceeds its parts has shares it has not accounted
    /// for, and this flow has to know exactly how the position is split: the
    /// unstaked half is what decides how many shares the farm is asked to
    /// release, and a request built against a wrong split is one the API will
    /// answer with a different transaction from the one being checked for.
    ///
    /// Compared at the API's OWN precision, never at the share mint's scale.
    /// Truncating three strings to six decimals and adding two of them can miss
    /// the third by a base unit with nothing wrong — `0.9445485 + 0.9595935`
    /// truncates to `944548 + 959593`, one short of `1904142` — and refusing a
    /// real position over a last decimal place is not a guard, it is a bug. At
    /// full precision the identity holds exactly: 80 live positions across all
    /// three launch vaults were checked and every one summed exactly.
    let accountsForItsTotal: Bool
}

/// The share balance a withdraw may spend, and how the vault currently holds it.
///
/// Both halves travel together because both are needed to size ONE transaction.
/// The maximum decides how much may be asked for; the unstaked part decides how
/// much the farm has to release first, which is an instruction argument the
/// validator pins. A form holding only the first would be able to build a
/// request it could not then check.
struct KaminoWithdrawableShares: Equatable {
    /// The most a withdraw may name — see `KaminoSharePosition.spendable`.
    let maximum: KaminoShareAmount
    /// The part of the position already sitting in the user's own share account,
    /// which a withdraw spends without touching the farm at all.
    let unstaked: KaminoShareAmount
}

/// What a withdraw from one vault may do right now.
///
/// Every deposit into the launch vaults auto-stakes its shares into the vault's
/// farm, so a staked position is not an edge case here — it is what essentially
/// every real holder is in. The transaction that spends those shares releases
/// them from the farm first (`farms::unstake`, then
/// `farms::withdraw_unstaked_deposits`, both ahead of the vault withdraw), and
/// the template in `KaminoInstructionSequence` now covers it, so a staked
/// balance is withdrawable rather than refused.
///
/// The refusals that remain are the ones that are about the READ, not about the
/// shape: a response whose figures contradict each other, and one whose parts do
/// not add up to its total. Neither describes a position this flow can size a
/// request against.
enum KaminoWithdrawEligibility: Equatable {

    /// The user holds shares that can be withdrawn, staked or not.
    case withdrawable(KaminoWithdrawableShares)

    /// The user holds no shares in this vault.
    case empty

    /// The position could not be read. Refused rather than treated as zero (a
    /// silent "nothing to withdraw" on a real position) or as whole (an amount
    /// the user does not have).
    case unreadable

    /// The share balance a withdraw may spend, or `nil` when none may be spent.
    var withdrawableShares: KaminoWithdrawableShares? {
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

        // Shares the response did not account for. A total larger than its parts
        // is a position this app cannot describe: it would have to guess how
        // much of the remainder is staked, and that guess is the argument of an
        // instruction it then claims to have verified.
        guard position.accountsForItsTotal else { return .unreadable }
        // Nothing left to spend once the maximum has stepped back from the
        // sentinel. A position of a single base unit lands here, and "nothing to
        // withdraw" is the true statement about it.
        guard !position.spendable.isZero else { return .empty }

        return .withdrawable(
            KaminoWithdrawableShares(maximum: position.spendable, unstaked: position.unstaked)
        )
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
    ///   exact share figure that was read, which is the position minus at most
    ///   the one base unit `KaminoSharePosition.spendable` steps back from the
    ///   API's sentinel — rather than a number converted out of the asset amount.
    ///   Round-tripping the maximum through tokens and back is precisely how an
    ///   extra base unit would be introduced.
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
