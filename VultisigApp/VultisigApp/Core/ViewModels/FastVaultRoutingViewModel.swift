import Foundation
import Combine

/// Owns action-time loading independently of presentation. Prefetching never
/// navigates; only the current user action may consume a resolved route.
@MainActor
final class FastVaultRoutingViewModel: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var hasError = false

    private let refresher: FastVaultEligibilityRefresher
    private var request: Task<Void, Never>?
    private var requestID: UUID?

    init(refresher: FastVaultEligibilityRefresher = .shared) {
        self.refresher = refresher
    }

    func prefetch(_ vault: Vault) async {
        _ = await refresher.presenceForRouting(vault)
    }

    func resolve(_ vault: Vault, onResolved: @escaping (Bool) -> Void) {
        guard request == nil else { return }
        hasError = false
        if let presence = refresher.confirmedPresenceForRouting(vault) {
            onResolved(presence == .present)
            return
        }
        isChecking = true
        let id = UUID()
        requestID = id
        request = Task { @MainActor in
            let presence = await refresher.presenceForRouting(vault)
            guard !Task.isCancelled, requestID == id else { return }
            request = nil
            requestID = nil
            isChecking = false
            switch presence {
            case .present: onResolved(true)
            case .absent: onResolved(false)
            case .unknown: hasError = true
            }
        }
    }

    /// Choosing paired devices or leaving the screen invalidates this action,
    /// even when another background consumer keeps the shared request alive.
    func cancel() {
        requestID = nil
        request?.cancel()
        request = nil
        isChecking = false
        hasError = false
    }
}
