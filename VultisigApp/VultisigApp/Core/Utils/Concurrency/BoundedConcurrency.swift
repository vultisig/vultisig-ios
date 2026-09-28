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
//  The contract is fail-closed: cancellation THROWS, it never returns fewer
//  results than requested. Completion order does not match input order, so
//  "stop scheduling and hand back whatever completed so far" does not
//  produce a clean prefix or suffix — it produces a HOLE wherever the
//  in-flight items that were never captured happened to sit (see the
//  `testCancellationThrowsInsteadOfReturningAGappedArray` regression test).
//  A caller reading a shorter array has no way to tell "cancelled, this is
//  partial" from "these were genuinely all the results" — for
//  `getBondRewardHistory` specifically, that reads as "no more churns",
//  which is a silent correctness bug, not a degraded-but-safe outcome.
//

import Foundation

func withBoundedConcurrency<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    operation: @escaping @Sendable (Item) async -> Result
) async throws -> [Result] {
    precondition(maxConcurrent > 0, "withBoundedConcurrency requires maxConcurrent > 0")

    // Checked before the empty-item short-circuit too: "cancellation always
    // throws" is the whole contract, and an already-cancelled caller getting
    // a silent `[]` back for empty input is the same "can't tell cancelled
    // from complete" problem as a gapped array, just at zero items.
    try Task.checkCancellation()
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

    // Checked unconditionally, even on the path where every index DID get
    // filled: if cancellation was ever observed above, `results` may still
    // hold gaps from children that completed after the loop broke (their
    // completion is awaited implicitly when the task group's scope exits,
    // but never captured — this loop already stopped reading from `group`),
    // and even a "lucky" fully-filled array must still be rejected, because
    // a caller cannot tell a genuine complete answer from that coincidence.
    try Task.checkCancellation()

    return results.map { result in
        guard let result else {
            preconditionFailure("withBoundedConcurrency scheduled every index exactly once")
        }
        return result
    }
}
