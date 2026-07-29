//
//  AppReviewService.swift
//  VultisigApp
//
//  Owns the persisted inputs to `AppReviewPolicy`: when the app was
//  installed, how many distinct transactions the user has watched
//  confirm, and when we last asked for a review.
//
//  Stored in `UserDefaults` rather than SwiftData on purpose — this is
//  preference-shaped device state, not model data. It must survive
//  independently of any vault, since a user can delete every vault and
//  restore another one without that resetting how often we may ask.
//
//  Idempotency is the whole point of `recordConfirmedTransaction(id:)`.
//  The done screen can observe the same `.confirmed` status more than
//  once — a re-render, a re-entry, or the poller re-reporting a terminal
//  status — so the tally is keyed on the transaction hash and a bounded
//  ring of already-counted hashes is kept alongside it. Counting per
//  observation would inflate the tally and fire the prompt early, which
//  on a 120-day cooldown is not a cheap mistake.
//

import Foundation

@MainActor
final class AppReviewService {
    static let shared = AppReviewService()

    /// How many recently-counted transaction hashes are retained for the
    /// duplicate check. The ring only has to be long enough that a hash is
    /// still remembered while the same done screen can re-report it, so a
    /// session's worth of transactions is already generous; the bound exists
    /// so the key cannot grow without limit over the lifetime of the install.
    /// Once the ring does wrap, the tally is necessarily far past the
    /// 3-transaction threshold, where an extra increment changes nothing.
    static let countedTransactionIDLimit = 100

    private enum Key {
        static let installDate = "appReview.installDate"
        static let confirmedTransactionCount = "appReview.confirmedTransactionCount"
        static let lastPromptDate = "appReview.lastPromptDate"
        static let countedTransactionIDs = "appReview.countedTransactionIDs"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let logger = Log.app.service

    /// `now` is injected so tests can pin the 7-day / 120-day boundaries
    /// without sleeping; production callers take the default.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Install date

    /// Stamps the install date the first time it is called and never again.
    ///
    /// Users upgrading into the first build that ships this are stamped with
    /// the upgrade date, not their real install date, so they serve the full
    /// 7-day wait. That is deliberate: the alternative — backdating so the
    /// rule is already satisfied — would fire the prompt at the entire
    /// existing base within days of the release, which is exactly the
    /// audience whose ratings we least want to spend on a rushed ask.
    func seedInstallDateIfNeeded() {
        guard defaults.object(forKey: Key.installDate) == nil else { return }
        defaults.set(now().timeIntervalSince1970, forKey: Key.installDate)
        logger.info("[AppReview] Seeded install date")
    }

    // MARK: - Recording

    /// Counts a confirmed transaction towards the review threshold, at most
    /// once per transaction hash.
    ///
    /// - Parameter id: the transaction hash. An empty id carries no identity,
    ///   so it cannot be de-duplicated and is not counted — undercounting is
    ///   the safe direction here.
    /// - Returns: whether this call actually incremented the tally.
    @discardableResult
    func recordConfirmedTransaction(id: String) -> Bool {
        guard !id.isEmpty else { return false }

        var counted = countedTransactionIDs
        guard !counted.contains(id) else { return false }

        counted.append(id)
        if counted.count > Self.countedTransactionIDLimit {
            counted.removeFirst(counted.count - Self.countedTransactionIDLimit)
        }
        defaults.set(counted, forKey: Key.countedTransactionIDs)

        let updatedCount = confirmedTransactionCount + 1
        defaults.set(updatedCount, forKey: Key.confirmedTransactionCount)
        logger.info("[AppReview] Confirmed transaction count is now \(updatedCount, privacy: .public)")
        return true
    }

    /// Records that the review sheet was requested.
    ///
    /// Called whenever `requestReview` is invoked, even though StoreKit may
    /// silently decline to show anything — the API reports nothing back, so
    /// the only safe assumption is that the ask was spent.
    func recordPromptShown() {
        defaults.set(now().timeIntervalSince1970, forKey: Key.lastPromptDate)
        logger.info("[AppReview] Recorded review prompt request")
    }

    // MARK: - Decision

    /// Whether the throttle currently allows asking for a review.
    func shouldRequestReview() -> Bool {
        AppReviewPolicy.shouldRequestReview(state: state, now: now())
    }

    /// Current persisted snapshot, as the policy sees it.
    var state: AppReviewState {
        AppReviewState(
            confirmedTransactionCount: confirmedTransactionCount,
            installDate: date(forKey: Key.installDate),
            lastPromptDate: date(forKey: Key.lastPromptDate)
        )
    }

    // MARK: - Storage

    private var confirmedTransactionCount: Int {
        defaults.integer(forKey: Key.confirmedTransactionCount)
    }

    private var countedTransactionIDs: [String] {
        defaults.stringArray(forKey: Key.countedTransactionIDs) ?? []
    }

    private func date(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}
