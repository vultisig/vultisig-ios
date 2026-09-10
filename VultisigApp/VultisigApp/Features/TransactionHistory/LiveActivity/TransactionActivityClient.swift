#if os(iOS)
import ActivityKit
import Foundation
import UIKit

struct TransactionActivityHandle {
    let id: String
    let recordID: UUID
    let state: TransactionActivityState
    let isActive: Bool
}

@MainActor
protocol TransactionActivityClient {
    var isAuthorized: Bool { get }
    var isForeground: Bool { get }
    var activities: [TransactionActivityHandle] { get }
    func request(recordID: UUID, state: TransactionActivityState) throws -> String
    func update(id: String, state: TransactionActivityState) async
    func end(id: String, state: TransactionActivityState, immediately: Bool) async
}

@MainActor
final class SystemTransactionActivityClient: TransactionActivityClient {
    // Keep ended handles until dismissal, so retained terminal content can be erased
    // immediately when the user hides balances, disables tracking, or deletes history.
    private var retained: [String: Activity<TransactionActivityAttributes>] = [:]

    var isAuthorized: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var isForeground: Bool { UIApplication.shared.applicationState == .active }
    var activities: [TransactionActivityHandle] {
        for activity in Activity<TransactionActivityAttributes>.activities { retained[activity.id] = activity }
        retained = retained.filter { $0.value.activityState != .dismissed }
        return retained.values.map {
            TransactionActivityHandle(id: $0.id, recordID: $0.attributes.recordID,
                                      state: $0.content.state,
                                      isActive: $0.activityState == .active || $0.activityState == .stale)
        }
    }

    func request(recordID: UUID, state: TransactionActivityState) throws -> String {
        let attributes = TransactionActivityAttributes(recordID: recordID)
        guard try JSONEncoder().encode(attributes).count + JSONEncoder().encode(state).count < 4_096 else {
            throw ActivityClientError.payloadTooLarge
        }
        let activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state, staleDate: state.staleDate),
                                            pushType: nil)
        retained[activity.id] = activity
        return activity.id
    }

    func update(id: String, state: TransactionActivityState) async {
        guard let activity = retained[id] ?? Activity<TransactionActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: state.staleDate))
    }

    func end(id: String, state: TransactionActivityState, immediately: Bool) async {
        guard let activity = retained[id] ?? Activity<TransactionActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        retained[id] = activity
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(60)))
    }

    private enum ActivityClientError: Error { case payloadTooLarge }
}
#endif
