import Foundation

/// Shares foreground defaults while keeping fast transactions from accelerating slower ones.
struct TransactionActivityPollingSchedule {
    private var lastObservation: [UUID: Date] = [:]

    static func interval(for row: TransactionHistoryData) -> TimeInterval {
        switch row.swapTracking?.providerKind {
        case SwapKitTrackingService.providerKind: return SwapKitTrackingService.baseInterval
        case NativeSwapTrackingService.providerKind: return NativeSwapTrackingService.baseInterval
        case THORChainLimitTrackingService.providerKind: return THORChainLimitTrackingService.baseInterval
        default:
            guard let chain = Chain(rawValue: row.chainRawValue) else { return NativeSwapTrackingService.baseInterval }
            return ChainStatusConfig.config(for: chain).pollInterval
        }
    }

    func shouldObserve(_ row: TransactionHistoryData, now: Date = Date()) -> Bool {
        guard let previous = lastObservation[row.id] else { return true }
        return now.timeIntervalSince(previous) >= Self.interval(for: row)
    }

    mutating func didObserve(_ row: TransactionHistoryData, now: Date = Date()) {
        lastObservation[row.id] = max(lastObservation[row.id] ?? now, now)
    }

    /// Unobserved records request their foreground interval; the continuation observes them immediately.
    func nextDelay(for rows: [TransactionHistoryData], now: Date = Date()) -> TimeInterval {
        rows.map { row in
            let interval = Self.interval(for: row)
            guard let previous = lastObservation[row.id] else { return interval }
            return max(0, previous.addingTimeInterval(interval).timeIntervalSince(now))
        }.min() ?? NativeSwapTrackingService.baseInterval
    }
}

/// `TransactionActivityStaleness.floor` lives in `TransactionActivityState.swift` because that
/// file also compiles into the widget extension target, which never sees `TransactionHistoryData`.
extension TransactionActivityStaleness {
    /// Scales the window past the floor only for providers whose own cadence already runs slow.
    static let multiplier: TimeInterval = 8

    static func window(for row: TransactionHistoryData) -> TimeInterval {
        max(floor, TransactionActivityPollingSchedule.interval(for: row) * multiplier)
    }
}
