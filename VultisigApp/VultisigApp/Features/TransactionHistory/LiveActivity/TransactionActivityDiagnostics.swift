#if os(iOS)
import Foundation
import UIKit

/// Use only local UUIDs, lifecycle values and sanitized error codes in diagnostics.
/// OSLog provides timestamps; the app's existing LOGGING / VULTI_LOG gate applies.
@MainActor
enum TransactionActivityDiagnostics {
    static func record(_ event: String, recordID: UUID? = nil, runID: UUID? = nil, detail: @autoclosure () -> String = "") {
        guard LogGate.isEnabled(.wallet, .service) else { return }
        let details = detail()
        let appState: String
        switch UIApplication.shared.applicationState {
        case .active: appState = "active"
        case .inactive: appState = "inactive"
        case .background: appState = "background"
        @unknown default: appState = "unknown"
        }
        let remaining = UIApplication.shared.backgroundTimeRemaining
        let seconds = remaining.isFinite && remaining >= 0 && remaining < 86_400 ? String(Int(remaining)) : "unbounded"
        Log.wallet.service.notice("[LiveActivity] event=\(event, privacy: .public) app=\(appState, privacy: .public) remainingSeconds=\(seconds, privacy: .public) run=\(runID?.uuidString ?? "-", privacy: .public) record=\(recordID?.uuidString ?? "-", privacy: .public) \(details, privacy: .public)")
    }
}
#endif
