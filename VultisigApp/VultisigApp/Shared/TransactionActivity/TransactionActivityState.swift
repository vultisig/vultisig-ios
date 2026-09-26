import Foundation
import VultisigUIResources

/// How long a backgrounded card may show its last observation before ActivityKit dims it stale.
/// Lives here (not the app-only polling schedule) because this file also compiles into the
/// widget extension target.
enum TransactionActivityStaleness {
    /// BGAppRefreshTask's earliest-begin-date is not a promised delivery time; real wakes
    /// are commonly >= 15 minutes apart. A short floor would mark almost every backgrounded
    /// card stale immediately, so this keeps most cadences comfortably fresh.
    static let floor: TimeInterval = 3 * 60
}

/// Versioned value-only contract. Never add wallet identity, hashes, full addresses or memos.
struct TransactionActivityState: Codable, Hashable, Sendable {
    enum Phase: String, Codable, CaseIterable, Sendable {
        case submitted, pending, sourceConfirmed, swapping
        /// Transfer settlement and provider-confirmed swap settlement are distinct.
        case confirmed, completed, refunded, partiallyRefunded, failed, filled, cancelled, expired, sourceConfirmedOnly, trackingEnded

        var isTerminal: Bool {
            switch self {
            case .confirmed, .completed, .refunded, .partiallyRefunded, .failed, .filled, .cancelled, .expired, .sourceConfirmedOnly, .trackingEnded: true
            default: false
            }
        }

        var displayStatus: DisplayStatus {
            switch self {
            case .confirmed, .completed, .filled: .success
            case .failed, .refunded, .partiallyRefunded, .cancelled, .expired: .failed
            // Source-only confirmation and tracking expiry do not prove swap settlement.
            case .submitted, .pending, .sourceConfirmed, .swapping, .sourceConfirmedOnly, .trackingEnded: .inProgress
            }
        }
    }

    enum DisplayStatus: CaseIterable, Hashable, Sendable {
        case inProgress, success, failed

        var localizationKey: String {
            switch self {
            case .inProgress: "inProgress"
            case .success: "success"
            case .failed: "transactionActivityFailed"
            }
        }
    }

    enum Operation: String, Codable, Sendable {
        case send, swap, approval, limit, transaction

        var localizationKey: String {
            switch self {
            case .send: "transactionActivitySending"
            case .swap: "transactionActivitySwap"
            case .approval: "transactionActivityApproval"
            case .limit: "transactionActivityLimit"
            case .transaction: "transactionActivityTransaction"
            }
        }
    }

    let schemaVersion: Int
    let phase: Phase
    let observedAt: Date
    let revision: Int
    let updateDelayed: Bool
    /// Omitted at the data boundary in private mode, including from updates.
    let summary: String?
    let network: String?
    /// Structured route labels avoid parsing the localized legacy summary.
    let sourceSummary: String?
    let destinationTicker: String?
    let operation: Operation?
    let recipient: String?
    let fee: String?
    let provider: String?
    let submittedAt: Date?
    /// Exact identifiers for bundled art, never image bytes, URLs or ticker guesses.
    let sourceAssetID: String?
    let destinationAssetID: String?
    /// Validated opaque keys of prepared shared-cache thumbnails.
    let sourceImageKey: String?
    let destinationImageKey: String?
    /// Chain/provider-aware `staleDate` window. Never privacy-sensitive; always present.
    let staleWindow: TimeInterval

    init(phase: Phase, observedAt: Date, revision: Int, updateDelayed: Bool = false,
         summary: String? = nil, network: String? = nil, showDetails: Bool = false,
         operation: Operation? = nil, recipient: String? = nil, fee: String? = nil,
         provider: String? = nil, submittedAt: Date? = nil,
         sourceAssetID: String? = nil, destinationAssetID: String? = nil,
         sourceImageKey: String? = nil, destinationImageKey: String? = nil,
         sourceSummary: String? = nil, destinationTicker: String? = nil,
         staleWindow: TimeInterval = TransactionActivityStaleness.floor) {
        self.schemaVersion = 1
        self.phase = phase
        self.observedAt = observedAt
        self.revision = revision
        self.updateDelayed = updateDelayed
        self.staleWindow = staleWindow
        self.summary = showDetails ? summary.map { Self.bounded($0, bytes: 240) } : nil
        self.sourceSummary = showDetails ? sourceSummary.map { Self.bounded($0, bytes: 160) } : nil
        self.destinationTicker = showDetails ? destinationTicker.map { Self.bounded($0, bytes: 80) } : nil
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
        self.sourceImageKey = showDetails ? Self.validatedImageKey(sourceImageKey) : nil
        self.destinationImageKey = showDetails ? Self.validatedImageKey(destinationImageKey) : nil
    }

    var hasDetails: Bool {
        summary != nil || sourceSummary != nil || destinationTicker != nil || network != nil || operation != nil || recipient != nil
            || fee != nil || provider != nil || submittedAt != nil
            || sourceAssetID != nil || destinationAssetID != nil
            || sourceImageKey != nil || destinationImageKey != nil
    }

    /// Generated catalog membership prevents remote or arbitrary bundle lookups.
    static func bundledAssetID(for logo: String?) -> String? {
        guard let logo, VultisigResources.containsImage(named: logo) else { return nil }
        return logo
    }

    static func validatedImageKey(_ key: String?) -> String? {
        guard let key, key.utf8.count == 64,
              key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return key
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case phase
        case observedAt
        case revision
        case updateDelayed
        case summary
        case network
        case sourceSummary
        case destinationTicker
        case operation
        case recipient
        case fee
        case provider
        case submittedAt
        case sourceAssetID
        case destinationAssetID
        case sourceImageKey
        case destinationImageKey
        case staleWindow
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        phase = try values.decode(Phase.self, forKey: .phase)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        revision = try values.decode(Int.self, forKey: .revision)
        updateDelayed = try values.decode(Bool.self, forKey: .updateDelayed)
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
        sourceSummary = try values.decodeIfPresent(String.self, forKey: .sourceSummary).map { Self.bounded($0, bytes: 160) }
        destinationTicker = try values.decodeIfPresent(String.self, forKey: .destinationTicker).map { Self.bounded($0, bytes: 80) }
        network = try values.decodeIfPresent(String.self, forKey: .network)
        operation = try values.decodeIfPresent(Operation.self, forKey: .operation)
        recipient = try values.decodeIfPresent(String.self, forKey: .recipient)
        fee = try values.decodeIfPresent(String.self, forKey: .fee)
        provider = try values.decodeIfPresent(String.self, forKey: .provider)
        submittedAt = try values.decodeIfPresent(Date.self, forKey: .submittedAt)
        sourceAssetID = Self.bundledAssetID(for: try values.decodeIfPresent(String.self, forKey: .sourceAssetID))
        destinationAssetID = Self.bundledAssetID(for: try values.decodeIfPresent(String.self, forKey: .destinationAssetID))
        sourceImageKey = Self.validatedImageKey(try values.decodeIfPresent(String.self, forKey: .sourceImageKey))
        destinationImageKey = Self.validatedImageKey(try values.decodeIfPresent(String.self, forKey: .destinationImageKey))
        staleWindow = try values.decodeIfPresent(TimeInterval.self, forKey: .staleWindow) ?? TransactionActivityStaleness.floor
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
    var staleDate: Date? { phase.isTerminal ? nil : observedAt.addingTimeInterval(staleWindow) }

    /// Anchor for a `Text(timerInterval:)` elapsed-time display. Settled transactions
    /// freeze their content, so ticking a clock past that point would mislead.
    var elapsedTimeAnchor: Date? { phase.isTerminal ? nil : submittedAt }
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
