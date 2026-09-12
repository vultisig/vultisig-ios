import Foundation

/// Versioned value-only contract. Never add wallet identity, hashes, full addresses or memos.
struct TransactionActivityState: Codable, Hashable, Sendable {
    enum Phase: String, Codable, CaseIterable, Sendable {
        case submitted, pending, sourceConfirmed, swapping
        /// Transfer settlement and provider-confirmed swap settlement are distinct.
        case confirmed, completed, refunded, partiallyRefunded, failed, trackingEnded

        var isTerminal: Bool {
            switch self {
            case .confirmed, .completed, .refunded, .partiallyRefunded, .failed, .trackingEnded: true
            default: false
            }
        }

        var localizationKey: String { "transactionActivity" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        var symbol: String {
            switch self {
            case .confirmed, .completed: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            case .refunded, .partiallyRefunded: "arrow.uturn.backward.circle"
            case .trackingEnded: "clock"
            default: "arrow.triangle.2.circlepath"
            }
        }
    }

    enum Operation: String, Codable, Sendable { case send, swap }

    let schemaVersion: Int
    let phase: Phase
    let observedAt: Date
    let revision: Int
    let updateDelayed: Bool
    /// Omitted at the data boundary in private mode, including from updates.
    let summary: String?
    let network: String?
    let operation: Operation?
    let recipient: String?
    let fee: String?
    let provider: String?
    let submittedAt: Date?
    /// Exact identifiers for bundled art, never image bytes, URLs or ticker guesses.
    let sourceAssetID: String?
    let destinationAssetID: String?

    init(phase: Phase, observedAt: Date, revision: Int, updateDelayed: Bool = false,
         summary: String? = nil, network: String? = nil, showDetails: Bool = false,
         operation: Operation? = nil, recipient: String? = nil, fee: String? = nil,
         provider: String? = nil, submittedAt: Date? = nil,
         sourceAssetID: String? = nil, destinationAssetID: String? = nil) {
        self.schemaVersion = 1
        self.phase = phase
        self.observedAt = observedAt
        self.revision = revision
        self.updateDelayed = updateDelayed
        self.summary = showDetails ? summary.map { Self.bounded($0, bytes: 240) } : nil
        self.network = showDetails ? network.map { Self.bounded($0, bytes: 80) } : nil
        self.operation = showDetails ? operation : nil
        self.recipient = showDetails ? recipient.flatMap { address in
            guard address.count > 12 else { return nil }
            return Self.bounded(String(address.prefix(4)), bytes: 16) + "…"
                + Self.bounded(String(address.suffix(4)), bytes: 16)
        } : nil
        self.fee = showDetails ? fee.map { Self.bounded($0, bytes: 96) } : nil
        self.provider = showDetails ? provider.map { Self.bounded($0, bytes: 80) } : nil
        self.submittedAt = showDetails ? submittedAt : nil
        self.sourceAssetID = showDetails ? Self.bundledAssetID(for: sourceAssetID) : nil
        self.destinationAssetID = showDetails ? Self.bundledAssetID(for: destinationAssetID) : nil
    }

    var hasDetails: Bool {
        summary != nil || network != nil || operation != nil || recipient != nil
            || fee != nil || provider != nil || submittedAt != nil
            || sourceAssetID != nil || destinationAssetID != nil
    }

    /// Allowlisting bounds the payload and prevents remote or arbitrary bundle lookups.
    static func bundledAssetID(for logo: String?) -> String? {
        guard let logo, ["btc", "eth", "usdc", "usdt", "bsc", "solana"].contains(logo) else { return nil }
        return logo
    }

    /// Scalar-wise byte bounding also handles a single huge combining grapheme.
    private static func bounded(_ text: String, bytes: Int) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar) else { continue }
            let next = String(scalar)
            guard result.utf8.count + next.utf8.count <= bytes else { break }
            result += next
        }
        return result
    }

    /// An in-process observation is useful briefly; suspension cannot extend it.
    var staleDate: Date? { phase.isTerminal ? nil : observedAt.addingTimeInterval(90) }
}

enum TransactionActivityLink {
    static func url(recordID: UUID) -> URL? {
        URL(string: "vultisig://transaction/" + recordID.uuidString)
    }

    static func recordID(from url: URL) -> UUID? {
        guard url.scheme == "vultisig", url.host == "transaction",
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
