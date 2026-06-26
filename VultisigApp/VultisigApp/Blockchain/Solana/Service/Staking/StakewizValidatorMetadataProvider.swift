//
//  StakewizValidatorMetadataProvider.swift
//  VultisigApp
//
//  Concrete `ValidatorMetadataProvider` backed by Stakewiz
//  (https://api.stakewiz.com). The `/validators` endpoint returns the full
//  validator set in one response, so a single fetch enriches an arbitrary batch
//  of vote pubkeys; results are cached per vote pubkey for 1 hour via the actor
//  `CachedEntry` pattern. A failed or rate-limited fetch yields whatever is
//  already cached (possibly nothing) — the call never throws, so callers degrade
//  to on-chain-only display.
//
//  When a validator exposes a Keybase identity, the logo is resolved through the
//  shared `KeybaseAvatarService`, falling back to Stakewiz's own `image` URL.
//
//  Field mapping (Stakewiz → ValidatorMetadata):
//    name         -> name
//    keybase/image -> logoURL  (Keybase avatar preferred, else image)
//    apy_estimate -> apyEstimate  (percent on the wire, stored as a fraction)
//    wiz_score    -> score
//    commission / delinquent / vote_identity are surfaced via the row itself so
//    callers can prefer Stakewiz commission/delinquency when present.
//

import Foundation
import OSLog

actor StakewizValidatorMetadataProvider: ValidatorMetadataProvider {

    private struct CachedEntry {
        let value: ValidatorMetadata
        let fetchedAt: Date
    }

    private let httpClient: HTTPClientProtocol
    private let avatarService: KeybaseAvatarServiceProtocol
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private let logger: Logger

    /// Per-vote-pubkey enrichment cache.
    private var cache: [String: CachedEntry] = [:]
    /// Coalesces concurrent batch fetches into a single in-flight request — the
    /// `/validators` endpoint is the same call regardless of which pubkeys are
    /// asked for, so there is at most one outstanding fetch.
    private var inFlight: Task<[StakewizValidator], Never>?

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        avatarService: KeybaseAvatarServiceProtocol = KeybaseAvatarService(),
        ttl: TimeInterval = 60 * 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "stakewiz-validator-metadata")
    ) {
        self.httpClient = httpClient
        self.avatarService = avatarService
        self.ttl = ttl
        self.clock = clock
        self.logger = logger
    }

    func metadata(forVotePubkeys votePubkeys: [String]) async -> [String: ValidatorMetadata] {
        let requested = Set(votePubkeys.filter { !$0.isEmpty })
        guard !requested.isEmpty else { return [:] }

        // Serve everything from cache when every requested pubkey is fresh.
        let now = clock()
        let cachedHits = requested.reduce(into: [String: ValidatorMetadata]()) { result, pubkey in
            if let entry = cache[pubkey], now.timeIntervalSince(entry.fetchedAt) < ttl {
                result[pubkey] = entry.value
            }
        }
        if cachedHits.count == requested.count {
            return cachedHits
        }

        let rows = await fetchValidators()
        guard !rows.isEmpty else {
            // Outage — return whatever we already had cached for the request.
            return cachedHits
        }

        let fetchedAt = clock()
        var result = cachedHits
        // Build a lookup once, then resolve only the requested pubkeys.
        var byVotePubkey: [String: StakewizValidator] = [:]
        for row in rows where !row.voteIdentity.isEmpty {
            byVotePubkey[row.voteIdentity] = row
        }
        for pubkey in requested where result[pubkey] == nil {
            guard let row = byVotePubkey[pubkey] else { continue }
            let metadata = await map(row)
            cache[pubkey] = CachedEntry(value: metadata, fetchedAt: fetchedAt)
            result[pubkey] = metadata
        }
        return result
    }

    // MARK: - Mapping

    private func map(_ row: StakewizValidator) async -> ValidatorMetadata {
        let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ValidatorMetadata(
            name: (name?.isEmpty == false) ? name : nil,
            logoURL: await resolveLogo(row),
            apyEstimate: Self.apyFraction(from: row.apyEstimate),
            score: row.wizScore.map { Int($0.rounded()) }
        )
    }

    /// Prefer the Keybase avatar when the validator exposes a Keybase identity;
    /// otherwise use Stakewiz's own `image` URL.
    private func resolveLogo(_ row: StakewizValidator) async -> String? {
        if let identity = row.keybase?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty,
           let url = await avatarService.avatarURL(forIdentity: identity) {
            return url.absoluteString
        }
        guard let image = row.image?.trimmingCharacters(in: .whitespacesAndNewlines), !image.isEmpty else {
            return nil
        }
        return image
    }

    /// Stakewiz reports `apy_estimate` as a percentage (e.g. `5.72`). Store it
    /// as a fraction to match `ValidatorMetadata.apyEstimate` (e.g. `0.0572`).
    private static func apyFraction(from percent: Double?) -> Decimal? {
        guard let percent, percent.isFinite, percent > 0 else { return nil }
        return Decimal(percent) / 100
    }

    // MARK: - Fetch

    private func fetchValidators() async -> [StakewizValidator] {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<[StakewizValidator], Never> { [self] in
            do {
                let response = try await httpClient.request(
                    StakewizValidatorsAPI(),
                    responseType: [StakewizValidator].self
                )
                return response.data
            } catch {
                logger.warning(
                    "Stakewiz validators fetch failed — degrading to on-chain only: \(error.localizedDescription, privacy: .public)"
                )
                return []
            }
        }
        inFlight = task
        let rows = await task.value
        inFlight = nil
        return rows
    }
}

// MARK: - Endpoint

private struct StakewizValidatorsAPI: TargetType {
    var baseURL: URL {
        // Force-unwrap is safe: the host is a compile-time literal known to
        // produce a valid URL at this exact form.
        URL(string: "https://api.stakewiz.com")!
    }

    var path: String { "/validators" }
    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
    var headers: [String: String]? { ["Accept": "application/json"] }
    var validationType: ValidationType { .successCodes }
    var timeoutInterval: TimeInterval { 15 }
}

// MARK: - Wire shape

/// A single Stakewiz `/validators` row. Every enrichment field is optional so a
/// missing key on the wire collapses to "no enrichment" rather than throwing.
private struct StakewizValidator: Decodable {
    let voteIdentity: String
    let name: String?
    let image: String?
    let keybase: String?
    let apyEstimate: Double?
    let commission: Int?
    let wizScore: Double?
    let delinquent: Bool?

    enum CodingKeys: String, CodingKey {
        case voteIdentity = "vote_identity"
        case name
        case image
        case keybase
        case apyEstimate = "apy_estimate"
        case commission
        case wizScore = "wiz_score"
        case delinquent
    }
}
