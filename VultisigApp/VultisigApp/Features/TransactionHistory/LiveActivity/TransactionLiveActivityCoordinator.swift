#if os(iOS)
import ActivityKit
import Combine
import Foundation

/// App-only writer. Its tasks can be suspended by iOS; staleDate conveys that honestly.
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
    private var bindings: [String: Binding]
    private var subscriptions = Set<AnyCancellable>()
    private var permissionTask: Task<Void, Never>?
    private var queue: Task<Void, Never>?
    private var detailsVisible = false
    private var started = false

    init(client: (any TransactionActivityClient)? = nil,
         defaults: UserDefaults = .standard,
         lookup: (@MainActor (UUID) throws -> TransactionHistoryData?)? = nil,
         vaultExists: (@MainActor (String) throws -> Bool)? = nil,
         resume: (@MainActor (TransactionHistoryData) -> Void)? = nil) {
        self.client = client ?? SystemTransactionActivityClient()
        self.defaults = defaults
        self.lookup = lookup ?? { try TransactionHistoryStorage.shared.fetch(id: $0) }
        self.vaultExists = vaultExists ?? { try TransactionLiveActivityBroadcast.vaultExists(pubKey: $0) }
        self.resume = resume ?? Self.resumeTracking
        bindings = defaults.data(forKey: TransactionActivityPolicy.ledgerKey)
            .flatMap { try? JSONDecoder().decode([String: Binding].self, from: $0) } ?? [:]
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

    func refresh() { enqueue { [weak self] in await self?.reconcile() } }

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
              row.status == .inProgress, row.type == .send || row.type == .swap,
              now.timeIntervalSince(row.createdAt) < TransactionActivityPolicy.maximumAge,
              client.activities.filter(\.isActive).count < TransactionActivityPolicy.maximumActivities,
              (try? lookup(row.id)) != nil, (try? vaultExists(row.pubKeyECDSA)) == true else { return }
        let state = TransactionActivityPolicy.state(for: row, phase: .submitted, observedAt: row.createdAt,
                                                    revision: 1, delayed: false, showDetails: showDetails)
        do {
            let id = try client.request(recordID: row.id, state: state)
            bindings[key]?.activityID = id
            bindings[key]?.ended = false
            persist()
            resume(row)
        } catch {
            Log.wallet.other.info("Live Activity could not be started; transaction remains in history")
        }
    }

    func receive(_ event: TransactionHistoryActivityEvent) async {
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
        let activities = client.activities
        for activity in activities {
            #if DEBUG
            if TransactionLiveActivityDemo.shared.owns(recordID: activity.recordID) { continue }
            #endif
            guard let pair = bindings.first(where: { $0.value.recordID == activity.recordID }) else {
                await client.end(id: activity.id, state: endedState(revision: activity.state.revision + 1), immediately: true)
                continue
            }
            if pair.value.ended {
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
                if now.timeIntervalSince(row.createdAt) >= TransactionActivityPolicy.maximumAge {
                    await finish(key: key, immediately: false)
                } else {
                    // Re-reading a row is not a fresh network observation.
                    await publish(row, observedAt: nil, delayed: activity.state.updateDelayed)
                    if !binding.phase.isTerminal && client.isForeground { resume(row) }
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
        guard var binding = bindings[key], !binding.ended, !binding.phase.isTerminal,
              let id = binding.activityID else { return }
        guard client.isAuthorized else {
            await finish(key: key, immediately: true)
            return
        }
        guard let activity = client.activities.first(where: { $0.id == id && $0.isActive }) else {
            binding.ended = true
            bindings[key] = binding
            persist()
            return
        }
        await redactIfNeeded(key: key, activity: activity)
        binding = bindings[key] ?? binding
        do {
            guard try vaultExists(row.pubKeyECDSA), try lookup(row.id) != nil else {
                await finish(key: key, immediately: true)
                return
            }
        } catch {
            return
        }
        if let observedAt, observedAt < binding.observedAt { return }
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
                                                    revision: binding.revision, delayed: delayed, showDetails: showDetails)
        binding.ended = binding.phase.isTerminal
        bindings[key] = binding
        persist()
        if state.phase.isTerminal {
            await client.end(id: id, state: state, immediately: false)
        } else {
            await client.update(id: id, state: state)
        }
    }

    /// Privacy cannot depend on being able to reopen history or the vault store.
    private func redactIfNeeded(key: String, activity: TransactionActivityHandle) async {
        guard !showDetails, activity.state.hasDetails else { return }
        let revision = max(bindings[key]?.revision ?? 0, activity.state.revision) + 1
        bindings[key]?.revision = revision
        persist()
        let redacted = TransactionActivityState(phase: activity.state.phase, observedAt: activity.state.observedAt,
                                                revision: revision, updateDelayed: activity.state.updateDelayed)
        await client.update(id: activity.id, state: redacted)
    }

    private func finish(key: String, immediately: Bool) async {
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
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: TransactionActivityPolicy.ledgerKey)
    }

    static func resumeTracking(_ row: TransactionHistoryData) {
        if let tracker = SwapTrackingRegistry.shared.service(for: row) {
            tracker.start(tx: row)
        } else if row.type == .send {
            TransactionStatusPoller.shared.poll(tx: row) { _, _ in }
        }
    }
}
#endif
