//
//  DelayedTask.swift
//  VultisigApp
//

import Foundation

/// Schedules `action` to run on the main actor after `delay`. The returned
/// task can be cancelled to abort the pending action — including the post-
/// sleep main-thread hop, which is what prevents a stale closure from
/// running after the owning view has been torn down.
@MainActor
func delayedTask(
    after delay: Duration,
    action: @MainActor @escaping () -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        action()
    }
}
