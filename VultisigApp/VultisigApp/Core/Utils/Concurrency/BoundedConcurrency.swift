//
//  BoundedConcurrency.swift
//  VultisigApp
//
//  Runs `operation` over `items` with at most `maxConcurrent` in flight at
//  once, returning results in input order regardless of completion order.
//  Backs the rewards sheet's up-to-20 historical `?height=` fetches — issuing
//  all of them at once would be indistinguishable from the "query all 400+
//  churns" antipattern this feature exists to avoid; running them one at a
//  time would make the sheet noticeably slower to open than it needs to be.
//
//  Cancelling the enclosing `Task` (e.g. the sheet closing) propagates to
//  every in-flight child through ordinary structured-concurrency
//  cancellation — `withTaskGroup` cancels its children when its own task is
//  cancelled.
//

import Foundation

func withBoundedConcurrency<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    operation: @escaping @Sendable (Item) async -> Result
) async -> [Result] {
    guard !items.isEmpty else { return [] }

    var results = [Result?](repeating: nil, count: items.count)

    await withTaskGroup(of: (Int, Result).self) { group in
        var nextIndex = 0

        func scheduleNext() {
            guard nextIndex < items.count else { return }
            let index = nextIndex
            let item = items[index]
            nextIndex += 1
            group.addTask {
                (index, await operation(item))
            }
        }

        for _ in 0..<min(maxConcurrent, items.count) {
            scheduleNext()
        }
        for await (index, result) in group {
            results[index] = result
            // Without this check, a cancelled enclosing task (the sheet
            // closing) still schedules a replacement for every completion,
            // draining all `items` instead of winding down — cancellation
            // only stops already-running children, not this loop.
            guard !Task.isCancelled else { break }
            scheduleNext()
        }
    }

    // Every index is filled on the normal path (scheduling only stops once
    // `items` is exhausted). `compactMap` rather than a forced unwrap is
    // what makes the cancellation path above safe: cancelling before every
    // index is scheduled leaves trailing `nil`s, which this simply drops —
    // the caller's own task is cancelled too, so a partial result is
    // discarded either way, and a crash here would be strictly worse.
    return results.compactMap { $0 }
}
