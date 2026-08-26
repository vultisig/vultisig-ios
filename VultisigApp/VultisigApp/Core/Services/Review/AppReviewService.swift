//
//  AppReviewService.swift
//  VultisigApp
//

import Foundation

/// A positive event that can contribute to App Store review eligibility.
///
/// Associated values are stable identities, not display values. Persisting the
/// namespaced identity makes every producer safe to call repeatedly across
/// rerenders, navigation re-entry, and app launches.
enum AppReviewEvent: Equatable {
    case confirmedOutboundTransaction(id: String)
    case confirmedIncomingTransaction(id: String)
    case vaultBackupCompleted(vaultID: String)
    case vaultRestoreCompleted(vaultID: String)
    case devicePairingCompleted(sessionID: String)

    fileprivate var storageID: String? {
        let namespace: String
        let identity: String

        switch self {
        case .confirmedOutboundTransaction(let id):
            namespace = "outbound"
            identity = id
        case .confirmedIncomingTransaction(let id):
            namespace = "incoming"
            identity = id
        case .vaultBackupCompleted(let vaultID):
            namespace = "backup"
            identity = vaultID
        case .vaultRestoreCompleted(let vaultID):
            namespace = "restore"
            identity = vaultID
        case .devicePairingCompleted(let sessionID):
            namespace = "pairing"
            identity = sessionID
        }

        guard let normalized = identity.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return "\(namespace):\(normalized)"
    }
}

@MainActor
final class AppReviewService {
    static let shared = AppReviewService()

    /// Bounds only the duplicate-check identities. The lifetime count remains
    /// monotonic after older identities roll off.
    static let countedEventIDLimit = 100

    private enum Key {
        static let installDate = "appReview.installDate"
        static let qualifyingEventCount = "appReview.qualifyingEventCount"
        static let countedEventIDs = "appReview.countedEventIDs"
        static let lastPromptDate = "appReview.lastPromptDate"
        static let lastPromptedVersion = "appReview.lastPromptedVersion"
        static let policyEvaluationCount = "appReview.policyEvaluationCount"
        static let promptClaimCount = "appReview.promptClaimCount"

        // v1.43.69 compatibility. Upgraders keep both their earned count and
        // transaction dedupe identities when the event model broadens.
        static let legacyConfirmedTransactionCount = "appReview.confirmedTransactionCount"
        static let legacyCountedTransactionIDs = "appReview.countedTransactionIDs"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let bundleVersion: () -> String?
    private let logger = Log.app.service

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        bundleVersion: @escaping () -> String? = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.bundleVersion = bundleVersion
    }

    // MARK: - Install date

    func seedInstallDateIfNeeded() {
        guard defaults.object(forKey: Key.installDate) == nil else { return }
        defaults.set(now().timeIntervalSince1970, forKey: Key.installDate)
        logger.info("[AppReview] Seeded install date")
    }

    // MARK: - Recording

    /// Records a qualifying event once for its stable identity.
    @discardableResult
    func record(_ event: AppReviewEvent) -> Bool {
        guard let eventID = event.storageID else { return false }

        var counted = countedEventIDs
        guard !counted.contains(eventID) else { return false }

        counted.append(eventID)
        if counted.count > Self.countedEventIDLimit {
            counted.removeFirst(counted.count - Self.countedEventIDLimit)
        }
        defaults.set(counted, forKey: Key.countedEventIDs)

        let updatedCount = qualifyingEventCount + 1
        defaults.set(updatedCount, forKey: Key.qualifyingEventCount)
        logger.info("[AppReview] Qualifying event count is now \(updatedCount, privacy: .public)")
        return true
    }

    /// Compatibility for the existing Done screen while event producers move
    /// to the typed API.
    @discardableResult
    func recordConfirmedTransaction(id: String) -> Bool {
        record(.confirmedOutboundTransaction(id: id))
    }

    // MARK: - Decision and atomic claim

    /// Evaluates and atomically consumes the current marketing-version ask.
    /// StoreKit reports no display result, so a successful claim is persisted
    /// before the caller invokes `requestReview()`.
    func claimReviewPrompt() -> Bool {
        let evaluationCount = policyEvaluationCount + 1
        defaults.set(evaluationCount, forKey: Key.policyEvaluationCount)

        let version = bundleVersion()?.nilIfEmpty
        let eligible = AppReviewPolicy.shouldRequestReview(
            state: state,
            now: now(),
            currentVersion: version
        )
        logger.info(
            "[AppReview] Policy evaluated eligible=\(eligible, privacy: .public) count=\(evaluationCount, privacy: .public)"
        )
        guard eligible, let version else { return false }

        defaults.set(now().timeIntervalSince1970, forKey: Key.lastPromptDate)
        defaults.set(version, forKey: Key.lastPromptedVersion)

        let claimCount = promptClaimCount + 1
        defaults.set(claimCount, forKey: Key.promptClaimCount)
        logger.info(
            "[AppReview] Prompt claimed for version \(version, privacy: .public) claimCount=\(claimCount, privacy: .public)"
        )
        return true
    }

    /// Compatibility for the existing Done screen. This remains count-first,
    /// then claim, until the shared app-level prompt host lands.
    func claimReviewPrompt(forConfirmedTransaction id: String) -> Bool {
        guard recordConfirmedTransaction(id: id) else { return false }
        return claimReviewPrompt()
    }

    func shouldRequestReview() -> Bool {
        AppReviewPolicy.shouldRequestReview(
            state: state,
            now: now(),
            currentVersion: bundleVersion()
        )
    }

    var state: AppReviewState {
        AppReviewState(
            qualifyingEventCount: qualifyingEventCount,
            installDate: date(forKey: Key.installDate),
            lastPromptDate: date(forKey: Key.lastPromptDate),
            lastPromptedVersion: defaults.string(forKey: Key.lastPromptedVersion)
        )
    }

    var instrumentation: AppReviewInstrumentation {
        AppReviewInstrumentation(
            policyEvaluationCount: policyEvaluationCount,
            promptClaimCount: promptClaimCount
        )
    }

    // MARK: - Storage

    private var qualifyingEventCount: Int {
        if defaults.object(forKey: Key.qualifyingEventCount) != nil {
            return defaults.integer(forKey: Key.qualifyingEventCount)
        }
        return defaults.integer(forKey: Key.legacyConfirmedTransactionCount)
    }

    private var countedEventIDs: [String] {
        if defaults.object(forKey: Key.countedEventIDs) != nil {
            return defaults.stringArray(forKey: Key.countedEventIDs) ?? []
        }
        return (defaults.stringArray(forKey: Key.legacyCountedTransactionIDs) ?? [])
            .map { "outbound:\($0)" }
    }

    private var policyEvaluationCount: Int {
        defaults.integer(forKey: Key.policyEvaluationCount)
    }

    private var promptClaimCount: Int {
        defaults.integer(forKey: Key.promptClaimCount)
    }

    private func date(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}

struct AppReviewInstrumentation: Equatable {
    let policyEvaluationCount: Int
    let promptClaimCount: Int
}
