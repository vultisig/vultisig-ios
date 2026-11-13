//
//  SwapTrackerModel.swift
//  VultisigApp
//
//  Stage-based progress for a broadcast swap. Stages are observed facts
//  (sent, swapped, received), never a smooth bar that implies measurable
//  progress. Same-chain swaps collapse to two stages.
//

import Foundation

struct SwapTrackerStage: Equatable, Identifiable {
    enum Kind: Equatable {
        case sent
        case swapped
        case received
    }

    enum Status: Equatable {
        case done
        case active
        case waiting
        case failed
    }

    let kind: Kind
    let status: Status
    var id: Kind { kind }
}

enum SwapTrackerPhase: Equatable {
    case inProgress
    /// Longer than the provider's estimate. Still in flight, not failed.
    case takingLonger
    case completed
    case failed(reason: String)
}

enum SwapTrackerModel {

    /// Maps the existing done-screen status onto stages.
    static func stages(status: TransactionStatus, isCrossChain: Bool) -> [SwapTrackerStage] {
        let kinds: [SwapTrackerStage.Kind] = isCrossChain ? [.sent, .swapped, .received] : [.sent, .received]
        // A failure or timeout sits on the stage after "sent": the source
        // transaction is out, what happens next is what went wrong or slow.
        let activeIndex: Int
        let failed: Bool
        switch status {
        case .broadcasted:
            (activeIndex, failed) = (0, false)
        case .pending, .timeout:
            (activeIndex, failed) = (1, false)
        case .confirmed:
            (activeIndex, failed) = (kinds.count, false)
        case .failed:
            (activeIndex, failed) = (1, true)
        }
        return kinds.enumerated().map { index, kind in
            let stageStatus: SwapTrackerStage.Status
            if index < activeIndex {
                stageStatus = .done
            } else if index == activeIndex {
                stageStatus = failed ? .failed : .active
            } else {
                stageStatus = .waiting
            }
            return SwapTrackerStage(kind: kind, status: stageStatus)
        }
    }

    static func phase(status: TransactionStatus, elapsed: TimeInterval, estimate: TimeInterval?) -> SwapTrackerPhase {
        switch status {
        case .confirmed:
            return .completed
        case .failed(let reason):
            return .failed(reason: reason)
        case .timeout:
            return .takingLonger
        case .broadcasted, .pending:
            guard let estimate, estimate > 0 else { return .inProgress }
            return elapsed > estimate * 1.5 ? .takingLonger : .inProgress
        }
    }

    /// "Usually 6-9 min more", from the provider estimate and the time spent.
    /// Nil once past the estimate (the "taking longer" copy takes over) or
    /// when the provider gives no estimate.
    static func remainingRange(elapsed: TimeInterval, estimate: TimeInterval?) -> ClosedRange<Int>? {
        guard let estimate, estimate > 0 else { return nil }
        let remaining = estimate - elapsed
        guard remaining > 0 else { return nil }
        let low = max(1, Int((remaining * 0.75 / 60).rounded(.down)))
        let high = max(low + 1, Int((remaining * 1.25 / 60).rounded(.up)))
        return low...high
    }
}

/// Quoted against delivered, on the success screen.
struct SwapOutcome: Equatable {
    let quoted: Decimal
    let delivered: Decimal

    var difference: Decimal { delivered - quoted }

    /// Share of the quote, signed. Nil for an empty quote.
    var differenceShare: Decimal? {
        guard quoted > 0 else { return nil }
        return difference / quoted
    }

    var isBetterThanQuoted: Bool { difference >= 0 }

    /// The difference in the coin's base units (sats for BTC).
    func differenceInBaseUnits(decimals: Int) -> Decimal {
        var scaled = difference
        for _ in 0..<max(decimals, 0) { scaled *= 10 }
        return scaled.rounded(scale: 0)
    }

    /// "+0.01%", two decimals, "." separator.
    var differenceShareText: String? {
        guard let share = differenceShare else { return nil }
        let bps = NSDecimalNumber(decimal: (share * 10_000).rounded(scale: 0)).intValue
        return (bps < 0 ? "-" : "+") + SwapFeeBreakdown.percent(bps: abs(bps))
    }
}
