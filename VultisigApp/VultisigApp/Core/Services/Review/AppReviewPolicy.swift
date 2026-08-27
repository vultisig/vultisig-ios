//
//  AppReviewPolicy.swift
//  VultisigApp
//

import Foundation

/// Snapshot of the persisted review state the policy decides over.
struct AppReviewState: Equatable {
    /// Lifetime count of distinct positive events recorded on this device.
    var qualifyingEventCount: Int

    /// When the app first launched on this device. A missing value fails closed.
    var installDate: Date?

    /// When StoreKit was most recently asked to present a review prompt.
    var lastPromptDate: Date?

    /// Marketing version (`CFBundleShortVersionString`) claimed by the most
    /// recent request. A build number is deliberately not part of this gate.
    var lastPromptedVersion: String?
}

enum AppReviewPolicy {
    /// Two distinct positive moments are enough to form a useful opinion.
    static let minimumQualifyingEvents = 2

    /// Avoid asking during onboarding or the user's first week with the app.
    static let minimumTimeSinceInstall: TimeInterval = 7 * 24 * 60 * 60

    /// Even a new release cannot ask immediately after the preceding release.
    static let minimumTimeBetweenPrompts: TimeInterval = 14 * 24 * 60 * 60

    /// Whether StoreKit may be asked for this marketing version at `now`.
    static func shouldRequestReview(
        state: AppReviewState,
        now: Date,
        currentVersion: String?
    ) -> Bool {
        guard state.qualifyingEventCount >= minimumQualifyingEvents else {
            return false
        }

        guard let installDate = state.installDate,
              now.timeIntervalSince(installDate) >= minimumTimeSinceInstall else {
            return false
        }

        guard let currentVersion = currentVersion?.nilIfEmpty,
              state.lastPromptedVersion != currentVersion else {
            return false
        }

        guard let lastPromptDate = state.lastPromptDate else {
            return true
        }

        return now.timeIntervalSince(lastPromptDate) >= minimumTimeBetweenPrompts
    }
}
