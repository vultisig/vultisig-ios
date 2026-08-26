//
//  AppReviewService.swift
//  VultisigApp
//

import BigInt
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

    /// Tells the app-level StoreKit host that the current visible surface can
    /// safely consume a claim. Recording and presentation are separate so a
    /// pairing event can navigate into signing without presenting over it.
    func requestPromptEvaluation() {
        NotificationCenter.default.post(name: .appReviewPromptOpportunity, object: nil)
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

extension Notification.Name {
    static let appReviewPromptOpportunity = Notification.Name("appReviewPromptOpportunity")
}

/// Conservative balance-delta qualification for the coin detail surface.
/// A spendable increase comes from a confirmed balance; pending balance is not
/// an input. Priced assets must clear a fiat floor, while an unpriced asset is
/// accepted only when it is native and clears its chain dust floor.
enum AppReviewIncomingBalancePolicy {
    static let dwellDuration: Duration = .seconds(3)
    static let minimumFiatValue = Decimal(1)

    static func eventID(
        coinID: String,
        previousRawBalance: String,
        currentRawBalance: String,
        decimals: Int,
        fiatRate: Decimal?,
        isNativeToken: Bool,
        minimumRawAmount: BigInt,
        isLikelySpam: Bool,
        baselineRefreshSucceeded: Bool,
        confirmationRefreshSucceeded: Bool
    ) -> String? {
        guard baselineRefreshSucceeded,
              confirmationRefreshSucceeded,
              !isLikelySpam,
              (0...38).contains(decimals),
              let previous = BigInt(previousRawBalance),
              let current = BigInt(currentRawBalance),
              previous >= 0,
              current > previous else {
            return nil
        }

        let delta = current - previous
        if let fiatRate, fiatRate > 0 {
            guard let rawDecimal = Decimal(
                string: delta.description,
                locale: Locale(identifier: "en_US_POSIX")
            ) else {
                return nil
            }
            let decimalDelta = rawDecimal / pow(Decimal(10), decimals)
            guard decimalDelta * fiatRate >= minimumFiatValue else { return nil }
        } else {
            guard isNativeToken, delta >= max(minimumRawAmount, 1) else { return nil }
        }

        guard let normalizedCoinID = coinID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return "\(normalizedCoinID):\(current)"
    }
}

#if os(iOS)
import StoreKit
import SwiftUI

private struct AppReviewPromptHost: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasPendingEvaluation = false
    @State private var evaluationGeneration = 0
    @State private var isSceneActive = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .appReviewPromptOpportunity)) { _ in
                scheduleEvaluation()
            }
            .onAppear {
                isSceneActive = scenePhase == .active
            }
            .onChange(of: scenePhase) { _, newPhase in
                isSceneActive = newPhase == .active
                guard hasPendingEvaluation else { return }
                // Cancel an armed task on every phase transition. In
                // particular, `.inactive` must cancel before a stale active
                // environment snapshot can consume the version claim.
                evaluationGeneration += 1
            }
            .task(id: evaluationGeneration) {
                await evaluateAfterNavigationSettles()
            }
    }

    private func scheduleEvaluation() {
        hasPendingEvaluation = true
        evaluationGeneration += 1
    }

    private func evaluateAfterNavigationSettles() async {
        guard hasPendingEvaluation else { return }

        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return
        }

        // Keep the pending bit set so returning to an active scene retries on a
        // visible surface instead of spending an ask while the app is inactive.
        guard isSceneActive else { return }
        hasPendingEvaluation = false

        guard AppReviewService.shared.claimReviewPrompt() else { return }
        requestReview()
    }
}

extension View {
    func appReviewPromptHost() -> some View {
        modifier(AppReviewPromptHost())
    }
}
#endif
