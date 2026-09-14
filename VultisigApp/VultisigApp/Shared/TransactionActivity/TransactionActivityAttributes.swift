#if os(iOS)
import ActivityKit
import Foundation

struct TransactionActivityAttributes: ActivityAttributes {
    typealias ContentState = TransactionActivityState
    /// Opaque, local history identifier. It contains no vault or chain identity.
    let recordID: UUID
}
#endif
