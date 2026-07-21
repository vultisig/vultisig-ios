//
//  LimitOrderStatusDisplay.swift
//  VultisigApp
//
//  What a limit order's card and detail sheet SAY about it — derived once,
//  here, so the two surfaces can't disagree and neither has to hold the logic.
//
//  Why this can't just read `TransactionHistoryData.status`: the coarse row
//  status has three values (inProgress / successful / error), and
//  `TransactionHistoryStorage` collapses refunded, expired, cancelled AND
//  failed into `.error` on the way in. That's fine for a swap, where "it went
//  wrong" is the whole story, but it erases the only distinction that matters
//  for an order — an expiry is a normal outcome with your funds back, a failure
//  is not. So the display reads the fine-grained `SwapTrackingUiStatus` the
//  limit provider actually wrote.
//

import Foundation

/// The headline status plus the second line beneath it.
///
/// The second line is the mock's existing two-line status slot (used there for
/// an error message). Partial-fill progress reuses it verbatim: a partially
/// filled order is STILL IN PROGRESS — the remainder is genuinely still
/// resting — so `partiallyFilled` is a qualifier on the status, never a status
/// of its own.
struct LimitOrderStatusDisplay: Equatable {
    enum Kind: Equatable {
        /// Placed and live. Includes partially-filled.
        case inProgress
        /// A cancel transaction for this order has been confirmed on-chain and
        /// the order has not yet left the queue.
        ///
        /// ⚠️ **A flavour of in-progress, never of success.** It says what we
        /// asked for, not what happened: the order is still resting and can
        /// still fill, because THORChain accepts a cancel that matches nothing.
        /// It is a separate kind purely so the copy can say "Cancelling…" — it
        /// must keep the in-progress styling, and it must never be treated as
        /// terminal.
        case cancelling
        /// Filled.
        case successful
        /// Terminal, did not fill (in whole or in part), funds returned. NOT a
        /// failure — an order that expires unfilled did exactly what it was
        /// told to do.
        case closedUnfilled(ClosedReason)
        /// Something actually went wrong.
        case failed
    }

    /// Why a terminal order didn't fill. Each is reported only when it is what
    /// we OBSERVED — the tracker records `refunded` and never infers `expired`,
    /// because a placement rejected outright also refunds within seconds
    /// without any TTL elapsing, and nothing reachable from a client separates
    /// the two.
    enum ClosedReason: Equatable {
        case refunded
        case expired
        case cancelled
    }

    let kind: Kind
    /// Second line. `nil` renders a single-line status.
    let detail: String?

    // MARK: - Derivation

    /// - Parameters:
    ///   - uiStatus: the limit provider's fine-grained status.
    ///   - details: the order snapshot, for the fill split. `nil` when the
    ///     order record isn't available (a co-signer never persists one) — the
    ///     status still resolves, just without progress.
    ///   - errorMessage: the row's error text, shown only for a real failure.
    static func make(
        uiStatus: SwapTrackingUiStatus,
        details: LimitOrderDetails?,
        errorMessage: String?
    ) -> LimitOrderStatusDisplay {
        switch uiStatus {
        case .resting, .pending, .swapping, .unknownPendingExtended:
            return LimitOrderStatusDisplay(kind: .inProgress, detail: progressDetail(details))
        case .cancelling:
            // Same second line as any other live order — a partial fill on an
            // order being cancelled is still a partial fill, and hiding it would
            // suggest the cancel already undid something.
            return LimitOrderStatusDisplay(kind: .cancelling, detail: progressDetail(details))
        case .completed:
            // A full fill needs no second line — the amount pair above it
            // already tells the whole story.
            return LimitOrderStatusDisplay(kind: .successful, detail: nil)
        case .refunded:
            return LimitOrderStatusDisplay(kind: .closedUnfilled(.refunded), detail: progressDetail(details))
        case .expired:
            return LimitOrderStatusDisplay(kind: .closedUnfilled(.expired), detail: progressDetail(details))
        case .cancelled:
            return LimitOrderStatusDisplay(kind: .closedUnfilled(.cancelled), detail: progressDetail(details))
        case .failed:
            // The only branch that surfaces raw on-chain text, and only when
            // there is some.
            return LimitOrderStatusDisplay(kind: .failed, detail: errorMessage?.nilIfEmpty)
        }
    }

    /// `"40% filled"`, or `nil` when the order hasn't partially filled.
    ///
    /// Shown ONLY for a partial fill. A 0% order has nothing to report beyond
    /// its status, and a 100% one is just "Successful".
    private static func progressDetail(_ details: LimitOrderDetails?) -> String? {
        guard let details, details.isPartiallyFilled,
              let fraction = details.fillFraction,
              let percent = LimitOrderFormatting.percent(fraction) else {
            return nil
        }
        return String(format: "limitSwap.progress.filledFormat".localized, percent)
    }

    // MARK: - Copy

    var title: String {
        switch kind {
        case .inProgress:
            return "inProgress".localized
        case .cancelling:
            // Present continuous on purpose: the sentence has to read as
            // waiting, not as done.
            return "limitSwap.status.cancelling".localized
        case .successful:
            return "successful".localized
        case .closedUnfilled(.refunded):
            return "limitSwap.status.refunded".localized
        case .closedUnfilled(.expired):
            return "limitSwap.status.expired".localized
        case .closedUnfilled(.cancelled):
            return "limitSwap.status.cancelled".localized
        case .failed:
            return "error".localized
        }
    }
}

// MARK: - Shared formatting

enum LimitOrderFormatting {
    /// `0.4` -> `"40%"`. `nil` if the fraction can't be formatted.
    ///
    /// No fractional digits: the number is a reassurance ("some of it went
    /// through"), and `39.7%` implies a precision that a streaming fill, still
    /// moving, does not have.
    ///
    /// A strictly partial fraction is clamped into `1%...99%`. Rounding to no
    /// fractional digits would otherwise let a dust fill read `0%` and a
    /// near-complete one read `100%` — each stating the exact opposite of what
    /// is true, on an order whose remainder is still resting. The clamp only
    /// ever moves a value that is already strictly between the boundaries, so
    /// a true `0` and a true `1` still render exactly.
    static func percent(_ fraction: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        let display = (fraction > 0 && fraction < 1)
            ? min(max(fraction, minPartialFraction), maxPartialFraction)
            : fraction
        return formatter.string(from: NSDecimalNumber(decimal: display))
    }

    /// The clamp bounds, as exact `Decimal` quotients — a `Decimal` built from
    /// a floating-point literal would not be exactly 1/100.
    private static let minPartialFraction = Decimal(1) / Decimal(100)
    private static let maxPartialFraction = Decimal(99) / Decimal(100)

    /// A compact, coarsening duration: `"2d 3h"`, `"11h 32m"`, `"45m"`, `"30s"`.
    ///
    /// Coarsens deliberately — an order resting for another two days does not
    /// need its seconds rendered, and a chip that changes every second on a
    /// 3-day countdown is noise. Below a minute it does show seconds, because
    /// there the change is the point.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
