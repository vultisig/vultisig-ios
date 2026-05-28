//
//  KeybaseAvatarService.swift
//  VultisigApp
//
//  Looks up the validator avatar URL from the Keybase public lookup API
//  given the validator's `description.identity` (16-hex string by Cosmos
//  convention). Caches the URL — including the "no avatar" negative cache
//  — per identity with a 1-hour TTL. Mirrors the Windows
//  `useKeybaseAvatarQuery` hook (1-hour staleTime + no retry).
//
//  Endpoint:
//    https://keybase.io/_/api/1.0/user/lookup.json
//      ?key_suffix={identity}
//      &fields=pictures
//
//  Parse path: `them[0].pictures.primary.url`. When the identity has no
//  associated Keybase profile picture, the resolver returns `nil` and the
//  validator card falls back to the deterministic colored-initial avatar.
//

import Foundation
import OSLog

protocol KeybaseAvatarServiceProtocol: Sendable {
    func avatarURL(forIdentity identity: String) async -> URL?
}

actor KeybaseAvatarService: KeybaseAvatarServiceProtocol {

    /// Cached lookup result. `value` holds the resolved URL, or `nil` when
    /// the identity is known to have no avatar — we still cache the
    /// negative result to avoid hammering Keybase on every list render.
    private struct CachedEntry {
        let value: URL?
        let fetchedAt: Date
    }

    private let httpClient: HTTPClientProtocol
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private let logger: Logger

    private var cache: [String: CachedEntry] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        ttl: TimeInterval = 60 * 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "keybase-avatar-service")
    ) {
        self.httpClient = httpClient
        self.ttl = ttl
        self.clock = clock
        self.logger = logger
    }

    func avatarURL(forIdentity identity: String) async -> URL? {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let entry = cache[trimmed], clock().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.value
        }
        if let task = inFlight[trimmed] {
            return await task.value
        }
        let task = Task<URL?, Never> { [self] in
            await self.fetch(identity: trimmed)
        }
        inFlight[trimmed] = task
        let result = await task.value
        inFlight[trimmed] = nil
        cache[trimmed] = CachedEntry(value: result, fetchedAt: clock())
        return result
    }

    // MARK: - Fetch

    private func fetch(identity: String) async -> URL? {
        do {
            let response = try await httpClient.request(
                KeybaseLookupAPI(identity: identity),
                responseType: KeybaseLookupResponse.self
            )
            guard let raw = response.data.them?
                .compactMap({ $0?.pictures?.primary?.url })
                .first(where: { !$0.isEmpty })
            else {
                return nil
            }
            return URL(string: raw)
        } catch {
            logger.warning(
                "Keybase lookup failed for identity \(identity, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

// MARK: - Endpoint

private struct KeybaseLookupAPI: TargetType {
    let identity: String

    var baseURL: URL {
        // Force-unwrap is safe: the host string is a literal and known to
        // produce a valid URL at this exact form.
        URL(string: "https://keybase.io")!
    }

    var path: String { "/_/api/1.0/user/lookup.json" }
    var method: HTTPMethod { .get }

    var task: HTTPTask {
        .requestParameters(
            [
                "key_suffix": identity,
                "fields": "pictures"
            ],
            .urlEncoding
        )
    }

    var headers: [String: String]? { nil }
    var validationType: ValidationType { .successCodes }
    var timeoutInterval: TimeInterval { 10 }
}

// MARK: - Wire shape

/// Keybase's `user/lookup.json` returns `them` as a *nullable list of
/// nullable entries* — when the identity isn't registered, the entire
/// `them` field is `null`; some lookups return a single null slot. Match
/// that shape exactly so a missing avatar collapses to `nil` without
/// throwing.
private struct KeybaseLookupResponse: Decodable {
    let them: [Entry?]?

    struct Entry: Decodable {
        let pictures: Pictures?

        struct Pictures: Decodable {
            let primary: Picture?
        }

        struct Picture: Decodable {
            let url: String?
        }
    }
}
