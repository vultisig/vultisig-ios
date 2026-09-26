#if os(iOS)
import ActivityKit
import Combine
import Foundation
import VultisigUIResources

/// Serialized app-owned writer; native background runtime is bounded and staleDate remains authoritative.
@MainActor
final class TransactionLiveActivityCoordinator {
    static let shared = TransactionLiveActivityCoordinator()

    struct Binding: Codable {
        let recordID: UUID
        var activityID: String?
        var phase: TransactionActivityState.Phase
        var observedAt: Date
        var revision: Int
        var ended: Bool
    }

    private let client: any TransactionActivityClient
    private let defaults: UserDefaults
    private let lookup: @MainActor (UUID) throws -> TransactionHistoryData?
    private let vaultExists: @MainActor (String) throws -> Bool
    private let resume: @MainActor (TransactionHistoryData) -> Void
    private let preparedImageKey: @MainActor (String) -> String?
    private let prepareImage: @MainActor (URL) async -> Void
    private static let imageCache = RemoteImageCache.shared()
    private static let imageLoader = RemoteImageLoader(cache: imageCache)

    private struct ImagePreparation {
        let recordID: UUID
        let urls: [URL]
        let token: UUID
        let task: Task<Void, Never>
    }
    // Completed attempts remain here to avoid retrying failed downloads on every status event.
    private var imagePreparations: [String: ImagePreparation] = [:]
    private var bindings: [String: Binding]
    private var subscriptions = Set<AnyCancellable>()
    private var permissionTask: Task<Void, Never>?
    private var queue: Task<Void, Never>?
    private var detailsVisible = false
    private var started = false
    var backgroundWorkDidChange: (() -> Void)?

    init(client: (any TransactionActivityClient)? = nil,
         defaults: UserDefaults = .standard,
         lookup: (@MainActor (UUID) throws -> TransactionHistoryData?)? = nil,
         vaultExists: (@MainActor (String) throws -> Bool)? = nil,
         resume: (@MainActor (TransactionHistoryData) -> Void)? = nil,
         preparedImageKey: (@MainActor (String) -> String?)? = nil,
         prepareImage: (@MainActor (URL) async -> Void)? = nil) {
        self.client = client ?? SystemTransactionActivityClient()
        self.defaults = defaults
        self.lookup = lookup ?? { try TransactionHistoryStorage.shared.fetch(id: $0) }
        self.vaultExists = vaultExists ?? { try TransactionLiveActivityBroadcast.vaultExists(pubKey: $0) }
        self.resume = resume ?? Self.resumeTracking
        self.preparedImageKey = preparedImageKey ?? { logo in
            guard let url = URL(string: logo), let key = RemoteImageCache.key(for: url),
                  Self.imageCache.data(forKey: key) != nil else { return nil }
            return key
        }
        self.prepareImage = prepareImage ?? { url in _ = try? await Self.imageLoader.load(url) }
        bindings = defaults.data(forKey: TransactionActivityPolicy.ledgerKey)
            .flatMap { try? JSONDecoder().decode([String: Binding].self, from: $0) } ?? [:]
        persist()
    }

    private var showDetails: Bool {
        !defaults.bool(forKey: "showVaultBalance")
    }

    func start() {
        guard !started else { return }
        started = true
        detailsVisible = showDetails
        NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification)
            .sink { [weak self] notification in
                guard let event = notification.object as? TransactionHistoryActivityEvent else { return }
                self?.enqueue { [weak self] in await self?.receive(event) }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.detailsVisible != self.showDetails else { return }
                self.detailsVisible = self.showDetails
                self.refresh()
            }.store(in: &subscriptions)
        permissionTask = Task { [weak self] in
            for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        if !showDetails || !client.isAuthorized { cancelAllImagePreparation() }
        enqueue { [weak self] in await self?.reconcile() }
    }

    /// Wait for all history events already enqueued before releasing native background runtime.
    func waitForPendingUpdates() async {
        await queue?.value
    }

    var backgroundRecords: [TransactionHistoryData] {
        client.activities.compactMap { backgroundRecord(id: $0.recordID) }
    }

    var hasBackgroundWork: Bool {
        client.activities.contains { backgroundRecord(id: $0.recordID) != nil }
    }

    /// Never admit records here. Only the foreground broadcast path can create an activity.
    func backgroundRecord(id: UUID, now: Date = Date()) -> TransactionHistoryData? {
        guard client.isAuthorized,
              let binding = bindings.values.first(where: { $0.recordID == id && !$0.ended && !$0.phase.isTerminal }),
              client.activities.contains(where: { $0.recordID == id && $0.id == binding.activityID && $0.isActive }),
              let row = try? lookup(id),
              bindings[TransactionActivityPolicy.identity(row)]?.recordID == id,
              now.timeIntervalSince(row.createdAt) < TransactionActivityPolicy.maximumAge,
              (try? vaultExists(row.pubKeyECDSA)) == true,
              !TransactionActivityPolicy.phase(for: row).isTerminal else { return nil }
        return row
    }

    func refreshInBackground(observe: @MainActor (TransactionHistoryData) async -> Void) async {
        start()
        refresh()
        await waitForPendingUpdates()
        let ids = mostStaleFirst(client.activities.compactMap { backgroundRecord(id: $0.recordID)?.id })
        TransactionActivityDiagnostics.record("poll.eligibleRecords", detail: "count=\(ids.count)")
        for id in ids {
            guard !Task.isCancelled else { return }
            guard let row = backgroundRecord(id: id) else { continue }
            await observe(row)
            await waitForPendingUpdates()
        }
        guard !Task.isCancelled else { return }
        refresh()
        await waitForPendingUpdates()
    }

    /// Oldest last-observed first, so the bounded background window spends its 22s
    /// budget on the records most overdue for an update.
    private func mostStaleFirst(_ ids: [UUID]) -> [UUID] {
        ids.sorted { lhs, rhs in
            let lhsObservedAt = bindings.values.first(where: { $0.recordID == lhs })?.observedAt ?? .distantPast
            let rhsObservedAt = bindings.values.first(where: { $0.recordID == rhs })?.observedAt ?? .distantPast
            return lhsObservedAt < rhsObservedAt
        }
    }

    func trackBroadcast(_ row: TransactionHistoryData) {
        start()
        enqueue { [weak self] in self?.admit(row) }
    }

    /// Serialize all ActivityKit awaits so older updates cannot overtake newer privacy/status writes.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let predecessor = queue
        queue = Task {
            await predecessor?.value
            await operation()
            self.backgroundWorkDidChange?()
        }
    }

    func admit(_ row: TransactionHistoryData, now: Date = Date()) {
        let key = TransactionActivityPolicy.identity(row)
        guard bindings[key] == nil else { return }
        // Persist the one-shot decision before request. A crash, rejection, capacity
        // overflow, permission denial, or dismissal must never cause an automatic resurrection.
        bindings[key] = Binding(recordID: row.id, phase: .submitted, observedAt: row.createdAt, revision: 1, ended: true)
        persist()
        guard client.isAuthorized, client.isForeground,
              row.status == .inProgress,
              now.timeIntervalSince(row.createdAt) < TransactionActivityPolicy.maximumAge,
              (try? lookup(row.id)) != nil, (try? vaultExists(row.pubKeyECDSA)) == true else { return }
        let state = TransactionActivityPolicy.state(for: row, phase: .submitted, observedAt: row.createdAt,
                                                    revision: 1, delayed: false, showDetails: showDetails, preparedImageKey: preparedImageKey)
        do {
            let id = try client.request(recordID: row.id, state: state)
            bindings[key]?.activityID = id
            bindings[key]?.ended = false
            persist()
            resume(row)
            prepareImages(for: row)
        } catch {
            TransactionActivityDiagnostics.record("activity.requestFailed", recordID: row.id, detail: "code=\((error as NSError).code)")
        }
    }

    func receive(_ event: TransactionHistoryActivityEvent) async {
        // A durable event can replace a row identity before foreground reconciliation.
        // Stop its previous download immediately, even if the replacement has no binding.
        for (key, job) in imagePreparations where imageRow(key: key, recordID: job.recordID, urls: job.urls) == nil {
            cancelImagePreparation(key: key)
        }
        switch event {
        case .deleted:
            await reconcile()
        case .saved(let row):
            let delayed = client.activities.first(where: { $0.recordID == row.id })?.state.updateDelayed ?? false
            await publish(row, observedAt: nil, delayed: delayed)
        case .nativeStatus(let row, let date):
            let sourceFailed = row.type == .swap && row.status == .error
                && !TransactionHistoryLegacyTimeout.localizedMessages().contains(row.errorMessage ?? "")
            await publish(row, observedAt: date, delayed: false, phaseOverride: sourceFailed ? .failed : nil)
        case .nativePending(let row, let date):
            await publish(row, observedAt: date, delayed: false)
        case .swapStatus(let row, let date):
            let delayed = TransactionActivityPolicy.providerIsDelayed(row)
            await publish(row, observedAt: delayed ? nil : date, delayed: delayed)
        case .delayed(let row):
            await publish(row, observedAt: nil, delayed: true)
        }
    }

    func reconcile(now: Date = Date()) async {
        if !showDetails || !client.isAuthorized { cancelAllImagePreparation() }
        let activities = client.activities
        for activity in activities {
            guard let pair = bindings.first(where: { $0.value.recordID == activity.recordID }) else {
                await client.end(id: activity.id, state: endedState(revision: activity.state.revision + 1), immediately: true)
                continue
            }
            if pair.value.ended {
                // Recover a terminal write interrupted after persistence but before ActivityKit acknowledged it.
                if activity.isActive, pair.value.phase.isTerminal, client.isAuthorized,
                   let row = try? lookup(pair.value.recordID), TransactionActivityPolicy.identity(row) == pair.key,
                   (try? vaultExists(row.pubKeyECDSA)) == true {
                    let state = TransactionActivityPolicy.state(for: row, phase: pair.value.phase,
                        observedAt: pair.value.observedAt, revision: pair.value.revision + 1,
                        delayed: false, showDetails: showDetails, preparedImageKey: preparedImageKey)
                    await client.end(id: activity.id, state: state, immediately: false)
                    continue
                }
                // Preserve the recognition window on routine foregrounds. Erase a
                // retained receipt when privacy/permission/deletion actually require it.
                var mustRemove = activity.isActive || !client.isAuthorized
                    || (!showDetails && activity.state.hasDetails)
                if !mustRemove {
                    do {
                        if let row = try lookup(pair.value.recordID) {
                            mustRemove = try !vaultExists(row.pubKeyECDSA)
                        } else {
                            mustRemove = true
                        }
                    } catch { continue }
                }
                if mustRemove {
                    await client.end(id: activity.id, state: endedState(revision: activity.state.revision + 1), immediately: true)
                }
                continue
            }
            // Reconcile the persisted binding against the system's current activity ID.
            bindings[pair.key]?.activityID = activity.id
        }
        for (key, binding) in bindings where !binding.ended {
            guard client.isAuthorized,
                  let activity = activities.first(where: { $0.recordID == binding.recordID && $0.isActive }) else {
                await finish(key: key, immediately: true)
                continue
            }
            await redactIfNeeded(key: key, activity: activity)
            do {
                guard let row = try lookup(binding.recordID), try vaultExists(row.pubKeyECDSA) else {
                    await finish(key: key, immediately: true)
                    continue
                }
                guard TransactionActivityPolicy.identity(row) == key else {
                    await finish(key: key, immediately: true)
                    continue
                }
                if now.timeIntervalSince(row.createdAt) >= TransactionActivityPolicy.maximumAge {
                    await finish(key: key, immediately: false)
                } else {
                    // Re-reading a row is not a fresh network observation.
                    await publish(row, observedAt: nil, delayed: activity.state.updateDelayed)
                    if let current = bindings[key], !current.ended, !current.phase.isTerminal, client.isForeground {
                        resume(row)
                    }
                }
            } catch {
                // A failed fetch is not deletion. Retain last known state until next foreground.
                continue
            }
        }
        persist()
    }

    private func publish(_ row: TransactionHistoryData, observedAt: Date?, delayed: Bool,
                         phaseOverride: TransactionActivityState.Phase? = nil) async {
        let key = TransactionActivityPolicy.identity(row)
        guard var binding = bindings[key], binding.recordID == row.id, !binding.ended, !binding.phase.isTerminal,
              let id = binding.activityID else {
            TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=noWritableBinding")
            return
        }
        TransactionActivityDiagnostics.record("publish.started", recordID: row.id, detail: "phase=\((phaseOverride ?? TransactionActivityPolicy.phase(for: row)).rawValue)")
        guard client.isAuthorized else {
            TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=notAuthorized")
            await finish(key: key, immediately: true)
            return
        }
        guard let activity = client.activities.first(where: { $0.id == id && $0.isActive }) else {
            TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=activityInactiveOrMissing")
            cancelImagePreparation(key: key)
            binding.ended = true
            bindings[key] = binding
            persist()
            return
        }
        await redactIfNeeded(key: key, activity: activity)
        binding = bindings[key] ?? binding
        do {
            guard try vaultExists(row.pubKeyECDSA), try lookup(row.id) != nil else {
                TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=recordOrVaultMissing")
                await finish(key: key, immediately: true)
                return
            }
        } catch {
            TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=lookupFailed")
            return
        }
        if let observedAt, observedAt < binding.observedAt {
            TransactionActivityDiagnostics.record("publish.skipped", recordID: row.id, detail: "reason=olderObservation")
            return
        }
        let next = phaseOverride ?? TransactionActivityPolicy.phase(for: row)
        // Delayed provider observations retain the last honest source-chain signal.
        if next.isTerminal || !delayed || next == .sourceConfirmed { binding.phase = next }
        if let observedAt {
            binding.observedAt = observedAt
        } else if next.isTerminal, let completedAt = row.completedAt {
            // A crash can lose the activity event after history already saved the
            // authoritative result. Use its durable observation time, not now.
            binding.observedAt = max(binding.observedAt, completedAt)
        }
        binding.revision += 1
        let state = TransactionActivityPolicy.state(for: row, phase: binding.phase, observedAt: binding.observedAt,
                                                    revision: binding.revision, delayed: delayed, showDetails: showDetails, preparedImageKey: preparedImageKey)
        binding.ended = binding.phase.isTerminal
        bindings[key] = binding
        persist()
        if state.phase.isTerminal {
            cancelImagePreparation(key: key)
            await client.end(id: id, state: state, immediately: false)
        } else {
            await client.update(id: id, state: state)
            prepareImages(for: row)
        }
    }

    private func cancelImagePreparation(key: String) {
        imagePreparations.removeValue(forKey: key)?.task.cancel()
    }

    private func cancelAllImagePreparation() {
        for job in imagePreparations.values { job.task.cancel() }
        imagePreparations.removeAll()
    }

    private func imageRow(key: String, recordID: UUID, urls: [URL]) -> TransactionHistoryData? {
        guard showDetails, let row = backgroundRecord(id: recordID),
              TransactionActivityPolicy.identity(row) == key,
              TransactionActivityPolicy.remoteImageURLs(for: row) == urls else { return nil }
        return row
    }

    private func prepareImages(for row: TransactionHistoryData) {
        let key = TransactionActivityPolicy.identity(row)
        let urls = TransactionActivityPolicy.remoteImageURLs(for: row)
        guard !urls.isEmpty, imageRow(key: key, recordID: row.id, urls: urls) != nil else {
            cancelImagePreparation(key: key)
            return
        }
        if let current = imagePreparations[key], current.recordID == row.id, current.urls == urls { return }
        cancelImagePreparation(key: key)
        let token = UUID()
        let recordID = row.id
        let prepare = prepareImage
        let task = Task { [weak self] in
            // Even a cache hit renews its protection for this newly accepted binding.
            for url in urls {
                guard !Task.isCancelled else { return }
                guard self?.imageRow(key: key, recordID: recordID, urls: urls) != nil else {
                    // A temporarily locked store is not a completed download attempt.
                    if self?.imagePreparations[key]?.token == token { self?.cancelImagePreparation(key: key) }
                    return
                }
                await prepare(url)
                guard !Task.isCancelled else { return }
            }
            // Refresh once even for preexisting keys: the loader may have repaired corrupt bytes.
            guard !Task.isCancelled else { return }
            self?.enqueue { [weak self] in
                guard let self, self.imagePreparations[key]?.token == token else { return }
                guard let current = self.imageRow(key: key, recordID: recordID, urls: urls),
                      let activity = self.client.activities.first(where: { $0.recordID == recordID && $0.isActive }) else {
                    self.cancelImagePreparation(key: key)
                    return
                }
                // Image readiness is not a transaction observation. Use current durable data
                // and retain the latest delayed flag, including across the queue wait.
                await self.publish(current, observedAt: nil, delayed: activity.state.updateDelayed)
            }
        }
        imagePreparations[key] = ImagePreparation(recordID: recordID, urls: urls, token: token, task: task)
    }

    /// Privacy cannot depend on being able to reopen history or the vault store.
    private func redactIfNeeded(key: String, activity: TransactionActivityHandle) async {
        if !showDetails { cancelImagePreparation(key: key) }
        guard !showDetails, activity.state.hasDetails else { return }
        let revision = max(bindings[key]?.revision ?? 0, activity.state.revision) + 1
        bindings[key]?.revision = revision
        persist()
        let redacted = TransactionActivityState(phase: activity.state.phase, observedAt: activity.state.observedAt,
                                                revision: revision, updateDelayed: activity.state.updateDelayed,
                                                staleWindow: activity.state.staleWindow)
        await client.update(id: activity.id, state: redacted)
    }

    private func finish(key: String, immediately: Bool) async {
        cancelImagePreparation(key: key)
        guard var binding = bindings[key] else { return }
        binding.ended = true
        binding.revision += 1
        bindings[key] = binding
        persist()
        if let id = binding.activityID {
            await client.end(id: id, state: endedState(revision: binding.revision), immediately: immediately)
        }
    }

    private func endedState(revision: Int) -> TransactionActivityState {
        TransactionActivityState(phase: .trackingEnded, observedAt: Date(), revision: revision)
    }

    private func persist() {
        // Keep system-retained receipts for privacy cleanup and terminal-write recovery.
        // Older ended decisions without a system activity can no longer be admitted.
        let retainedRecordIDs = Set(client.activities.map(\.recordID))
        let cutoff = Date().addingTimeInterval(-TransactionActivityPolicy.maximumAge)
        bindings = bindings.filter { _, binding in
            !binding.ended || binding.observedAt >= cutoff || retainedRecordIDs.contains(binding.recordID)
        }
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: TransactionActivityPolicy.ledgerKey)
    }

    static func resumeTracking(_ row: TransactionHistoryData) {
        if let tracker = SwapTrackingRegistry.shared.service(for: row) {
            tracker.start(tx: row)
        } else if TransactionActivityPolicy.usesNativeStatus(row), row.status == .inProgress {
            TransactionStatusPoller.shared.poll(tx: row) { _, _ in }
        }
    }
}
#endif
