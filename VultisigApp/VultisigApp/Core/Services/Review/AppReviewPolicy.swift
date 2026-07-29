//
//  AppReviewPolicy.swift
//  VultisigApp
//
//  Decides whether the app may ask for an App Store review right now.
//
//  Deliberately a pure function over (state, now) with no persistence,
//  no clock and no StoreKit: the throttle is the part that carries real
//  cost when it is wrong — asking too early burns the system's ~3
//  prompts/year budget and our own 120-day window — so it is kept
//  isolated and exhaustively unit-tested. `AppReviewService` owns the
//  storage and feeds a snapshot in.
//
//  All three windows are lower bounds, so every comparison is `>=`:
//  hitting exactly the threshold is eligible.
//

import Foundation

/// Snapshot of the persisted review state the policy decides over.
struct AppReviewState: Equatable {
    /// Lifetime count of distinct on-chain-confirmed transactions the user
    /// has watched complete.
    var confirmedTransactionCount: Int

    /// When the app first launched on this device. `nil` until seeded,
    /// which blocks the prompt — a missing install date is treated as
    /// "just installed", never as "installed long ago".
    var installDate: Date?

    /// When the review sheet was last requested, or `nil` if never.
    var lastPromptDate: Date?
}

enum AppReviewPolicy {
    /// Enough completed transactions that the user has a formed opinion.
    static let minimumConfirmedTransactions = 3

    /// Enough time on the device that the rating reflects the app, not the
    /// onboarding.
    static let minimumTimeSinceInstall: TimeInterval = 7 * 24 * 60 * 60

    /// Cooldown between two asks. Well above Apple's own ~3-per-year cap so
    /// we never spend the budget faster than the system would allow.
    static let minimumTimeBetweenPrompts: TimeInterval = 120 * 24 * 60 * 60

    /// Whether the review sheet may be requested at `now`.
    ///
    /// `now` is injected so the boundaries can be pinned deterministically;
    /// production callers pass the current date.
    static func shouldRequestReview(state: AppReviewState, now: Date) -> Bool {
        guard state.confirmedTransactionCount >= minimumConfirmedTransactions else {
            return false
        }

        // A missing install date means the seeding step has not run yet.
        // Fail closed rather than treating "unknown" as "old enough".
        guard let installDate = state.installDate else {
            return false
        }

        // A negative interval (device clock moved backwards, or a restored
        // backup carrying a future-dated seed) also fails this check, which
        // is the conservative direction.
        guard now.timeIntervalSince(installDate) >= minimumTimeSinceInstall else {
            return false
        }

        guard let lastPromptDate = state.lastPromptDate else {
            return true
        }
        return now.timeIntervalSince(lastPromptDate) >= minimumTimeBetweenPrompts
    }
}
