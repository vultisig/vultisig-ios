import Foundation

protocol RetryableBroadcastError: Error {
    var retryReason: BroadcastRetryReason { get }
}

enum BroadcastRetryReason: Equatable {
    case staleBlockhash
    case staleNonce
    case staleQuote
    case other(String)

    var userFacingMessage: String {
        toastKey.localized
    }

    var toastKey: String {
        switch self {
        case .staleBlockhash:
            return "broadcastRetryStaleBlockhash"
        case .staleNonce:
            return "broadcastRetryStaleNonce"
        case .staleQuote:
            return "broadcastRetryStaleQuote"
        case .other:
            return "broadcastRetryGeneric"
        }
    }
}
