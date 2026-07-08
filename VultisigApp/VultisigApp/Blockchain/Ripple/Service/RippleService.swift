//
//  RippleService.swift
//  VultisigApp
//

import Foundation
import WalletCore
import BigInt
import OSLog

enum RippleFee {
    /// XRPL reference (base) fee under no load.
    static let referenceFeeDrops = 10
    /// Margin applied to the open-ledger cost to survive escalation while the
    /// TSS devices sign.
    static let safetyMultiplier = BigInt(2)
    /// Upper bound; comfortably covers fee escalation under load while keeping
    /// the cost negligible (0.002 XRP).
    static let maxFeeDrops = 2000

    /// Derives a fee (in drops) from the server's reported load.
    ///
    /// The open-ledger cost is `base_fee * load_factor / load_base`. We apply a
    /// safety multiplier so the transaction survives further escalation during
    /// the TSS signing window, then clamp to `[referenceFeeDrops, maxFeeDrops]`.
    static func recommendedFee(baseFee: Int?, loadFactor: Int?, loadBase: Int?) -> BigInt {
        let base = BigInt(baseFee ?? referenceFeeDrops)
        let factor = BigInt(loadFactor ?? 1)
        let divisor = BigInt(max(loadBase ?? 1, 1))

        let openLedgerFee = max(base, base * factor / divisor)
        let recommended = openLedgerFee * safetyMultiplier
        return min(max(recommended, BigInt(referenceFeeDrops)), BigInt(maxFeeDrops))
    }
}

/// Owner-aware XRPL account-reserve math. The reserve floor is
/// `reserve_base + OwnerCount × reserve_inc` — every ledger object the account
/// owns (trustline, offer, ticket, escrow, …) adds one increment. The floor
/// applies to the Payment amount only; the transaction fee is exempt and may
/// take the account below the reserve.
/// - https://xrpl.org/docs/concepts/accounts/reserves
enum RippleReserve {
    /// Mainnet base reserve — 1 XRP (validator vote, Dec 2024). Last-resort
    /// seed only; live values come from `server_state`.
    static let seedReserveBaseDrops = BigInt(1_000_000)
    /// Mainnet per-object owner reserve — 0.2 XRP (validator vote, Dec 2024).
    /// Seed only, as above.
    static let seedReserveIncDrops = BigInt(200_000)

    /// Total reserved balance in drops: `reserve_base + OwnerCount × reserve_inc`.
    /// Missing `server_state` fields fall back to the mainnet seeds; a missing
    /// owner count counts as zero owned objects.
    static func reservedDrops(ownerCount: Int?, reserveBase: Int?, reserveInc: Int?) -> BigInt {
        let base = reserveBase.map { BigInt($0) } ?? seedReserveBaseDrops
        let inc = reserveInc.map { BigInt($0) } ?? seedReserveIncDrops
        return base + BigInt(ownerCount ?? 0) * inc
    }

    /// Spendable balance in drops: `max(total − reservedDrops, 0)`.
    static func availableDrops(totalDrops: BigInt, ownerCount: Int?, reserveBase: Int?, reserveInc: Int?) -> BigInt {
        let reserved = reservedDrops(ownerCount: ownerCount, reserveBase: reserveBase, reserveInc: reserveInc)
        return max(totalDrops - reserved, BigInt(0))
    }

    /// The activation minimum in whole XRP for a destination that must receive
    /// at least `baseReserveDrops` to be created, formatted for user-facing
    /// copy. Shared by the throwing Verify guard and the non-throwing send-form
    /// check so the two can never present a different minimum.
    static func minimumActivationXRP(baseReserveDrops: BigInt) -> String {
        // drops → XRP. toDecimal(decimals:) truncates rather than scales, so
        // divide; reserves are always positive, so no fallback default is needed.
        (baseReserveDrops.toDecimal(decimals: 6) / pow(10, 6)).description
    }
}

/// Non-throwing, send-form counterpart to `validateDestinationActivation`.
/// The Verify guard throws to block signing; the form needs a value it can
/// render inline while the user types the amount, and it fails open — a lookup
/// it can't complete shows no inline error, leaving the Verify guard as the
/// fail-closed backstop.
enum RippleReserveCheck: Equatable {
    /// No inline error: the destination is already funded, or it is unfunded
    /// but the entered amount already covers the base reserve.
    case satisfied
    /// The destination is unfunded and the entered amount is below the live
    /// base reserve; `minimumXRP` is the minimum in whole XRP for the copy.
    case belowMinimum(minimumXRP: String)
    /// The destination could not be verified — fail open, show no inline error.
    case unknown
}

/// Whether a destination account already exists on-ledger. Cached per address
/// so the send form's amount re-validation doesn't re-query `account_info` on
/// every keystroke — funded/unfunded is a property of the address, not the
/// amount.
enum RippleDestinationFunding {
    case funded
    case unfunded
}

/// A per-key cache of definitive destination funding verdicts. Deliberately
/// simpler than `TTLCache`: a fresh entry (within `ttl`) is served without a
/// network call, but an EXPIRED entry is never resurfaced when a refresh
/// fails — the send-form caller needs a genuine "couldn't verify" signal
/// (`.unknown`, fail open), not a possibly-wrong stale verdict. Only the
/// caller's definitive results are ever stored.
actor RippleDestinationFundingCache {
    private struct Entry {
        let value: RippleDestinationFunding
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]

    /// The stored verdict for `key` when it's still within `ttl`; otherwise
    /// `nil` (the caller refreshes).
    func cached(_ key: String, now: Date, ttl: TimeInterval) -> RippleDestinationFunding? {
        guard let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    /// Store or replace the verdict for `key`. Also the test seam for seeding.
    func store(_ key: String, value: RippleDestinationFunding, at: Date) {
        entries[key] = Entry(value: value, fetchedAt: at)
    }
}

/// Reserve values reported by `server_state`. Fields stay optional so a
/// partial response still caches, with `RippleReserve` seeding the gaps.
struct RippleReserveValues {
    let reserveBase: Int?
    let reserveInc: Int?
}

class RippleService {

    static let shared = RippleService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "ripple-service")

    /// Direct HTTP client for the verify-by-hash `tx` lookup, which runs its
    /// own bespoke retry loop (see `resolveSubmitByHash`).
    private let httpClient: HTTPClientProtocol

    /// Executes requests with a bounded same-host retry on transient node
    /// errors (`amendmentBlocked` and the node-unavailable family). Because the
    /// resolved host is a load-balanced pool, a same-host retry routes to a
    /// different (healthy) backend — no fallback host list is needed.
    private let retrier: RippleRequestRetrier

    /// Resolves the Ripple custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    /// Last-good `server_state` reserve values. Reserves change only by rare
    /// validator vote, so a generous TTL is safe; `TTLCache` coalesces
    /// concurrent refreshes and fails open to the last-good snapshot when a
    /// refresh throws. Internal (not `private`) together with the key so tests
    /// can seed stale entries via `setCached`.
    let reserveValuesCache = TTLCache<String, RippleReserveValues>()
    private static let reserveValuesTTL: TimeInterval = 60 * 60 * 24

    /// Cache key for the reserve values, scoped to a resolved host: a custom
    /// RPC override can point at a network with different reserves (e.g. a
    /// testnet), so a snapshot cached for one endpoint must never be served
    /// for another after a runtime override change.
    static func reserveValuesCacheKey(for host: URL) -> String {
        "xrpl-reserve-values|\(host.absoluteString)"
    }

    /// Per-destination funding verdict, cached so the send form's amount
    /// re-validation doesn't re-query `account_info` on every keystroke. Keyed
    /// on a resolved host like the reserve cache: a custom RPC override can
    /// point at a different network, so one endpoint's verdict must never be
    /// served for another. Only definitive verdicts are stored, and — unlike
    /// `TTLCache` — a failed refresh is NEVER served as stale: the form must
    /// fail open (`.unknown`) on a lookup it can't complete, not resurface an
    /// expired verdict. Internal (with the key) so tests can seed it.
    let destinationFundingCache = RippleDestinationFundingCache()
    private static let destinationFundingTTL: TimeInterval = 60 * 5

    /// Cache key for a destination's funding verdict, host-scoped for the same
    /// reason as `reserveValuesCacheKey`.
    static func destinationFundingCacheKey(for host: URL, address: String) -> String {
        "xrpl-destination-funding|\(host.absoluteString)|\(address)"
    }

    /// Backoff between `tx` lookups while resolving a verify-by-hash submit;
    /// injectable so tests run without delay.
    private let verifyByHashBackoff: Duration

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        httpClient: HTTPClientProtocol = HTTPClient(),
        sleep: @escaping RippleRequestRetrier.Sleeper = RippleRequestRetrier.defaultSleep,
        verifyByHashBackoff: Duration = .seconds(2)
    ) {
        self.resolver = resolver
        self.httpClient = httpClient
        self.retrier = RippleRequestRetrier(httpClient: httpClient, sleep: sleep)
        self.verifyByHashBackoff = verifyByHashBackoff
    }

    /// The override-aware XRPL host. Falls back to the default host when no
    /// override is set.
    private var resolvedHost: URL {
        resolver.resolvedURL(for: .ripple, default: RippleAPI.defaultHost)
    }

    /// Builds a pure `RippleAPI` value with the resolved host baked in. The
    /// `TargetType` itself never consults the resolver.
    private func api(_ endpoint: RippleAPI.Endpoint) -> RippleAPI {
        RippleAPI(endpoint, host: resolvedHost)
    }

    func broadcastTransaction(_ hex: String) async throws -> String {
        let response = try await retrier.request(
            api(.submit(txBlob: hex)),
            responseType: RippleSubmitResponse.self
        )

        let result = response.result
        let disposition = RippleSubmitDisposition.classify(
            engineResult: result?.engineResult,
            engineResultMessage: result?.engineResultMessage,
            hash: result?.txJson?.hash
        )

        switch disposition {
        case .accepted(let hash):
            return hash
        case .verifyByHash(let code, let hash, let message):
            return try await resolveSubmitByHash(code: code, hash: hash, message: message)
        case .rejected(let code, let message):
            logger.error("broadcast rejected by XRPL: \(code, privacy: .public)")
            throw RippleBroadcastError.broadcastFailed(code: code, message: message)
        }
    }

    /// Resolves a submit whose engine result says the transaction may already
    /// be known to the network — a faster co-signing peer's broadcast of the
    /// same signed blob landed first, or the server queued it for a future
    /// ledger — by looking the echoed deterministic hash up with the `tx`
    /// method against the same (override-aware) node the submit went to.
    ///
    /// `txnNotFound` is retried with a short backoff because cluster nodes can
    /// lag a peer's submit by a few seconds; lookup errors count as failed
    /// attempts for the same reason (the lookup is a safety net and must not
    /// invent a new failure mode). If the transaction never shows up, the
    /// ORIGINAL engine code is thrown — an unverified duplicate must never be
    /// reported as a success.
    private func resolveSubmitByHash(code: String, hash: String?, message: String?) async throws -> String {
        guard let hash else {
            throw RippleBroadcastError.broadcastFailed(code: code, message: message)
        }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let response = try await httpClient.request(
                    api(.tx(hash: hash)),
                    responseType: RippleTransactionStatusResponse.self
                )

                switch RippleTxLookupOutcome.interpret(response.data) {
                case .validatedSuccess:
                    logger.info("\(code, privacy: .public) resolved as validated success: \(hash, privacy: .public)")
                    return hash
                case .pending:
                    // Known to the network and in flight — return the hash and
                    // let the status poller resolve the final outcome.
                    logger.info("\(code, privacy: .public) resolved as in-flight: \(hash, privacy: .public)")
                    return hash
                case .validatedFailure(let validatedCode):
                    // The transaction landed in a validated ledger with a final
                    // non-success result — surface that real code.
                    logger.error("\(code, privacy: .public) resolved as validated failure \(validatedCode, privacy: .public)")
                    throw RippleBroadcastError.broadcastFailed(
                        code: validatedCode,
                        message: "The transaction was included in a validated ledger but did not succeed."
                    )
                case .notFound:
                    break
                }
            } catch let error as RippleBroadcastError {
                throw error
            } catch {
                logger.warning("verify-by-hash lookup failed (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription, privacy: .public)")
            }

            if attempt < maxAttempts {
                do {
                    try await Task.sleep(for: verifyByHashBackoff)
                } catch {
                    logger.warning("verify-by-hash backoff interrupted: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }
        }

        logger.error("verify-by-hash exhausted for \(code, privacy: .public): \(hash, privacy: .public) not found")
        throw RippleBroadcastError.broadcastFailed(code: code, message: message)
    }

    func getBalance(address: String) async throws -> String {
        async let accountInfoTask = fetchAccountsInfo(for: address)
        async let reserveValuesTask = fetchReserveValues()

        // Only the account read is fatal — there is no balance without it. The
        // reserve read has its own live → cache → seed fallback chain, so a
        // transient `server_state` outage no longer fails the balance refresh
        // (it only rethrows cancellation).
        let accountInfo = try await accountInfoTask
        let reserveValues = try await reserveValuesTask

        guard let totalBalanceStr = accountInfo?.result?.accountData?.balance,
              let totalBalance = BigInt(totalBalanceStr) else {
            return "0"
        }

        let availableBalance = RippleReserve.availableDrops(
            totalDrops: totalBalance,
            ownerCount: accountInfo?.result?.accountData?.ownerCount,
            reserveBase: reserveValues?.reserveBase,
            reserveInc: reserveValues?.reserveInc
        )

        return availableBalance.description
    }

    /// Resolves the XRPL reserve values: live `server_state` → cached
    /// last-good snapshot → `nil` (callers fall back to the `RippleReserve`
    /// seeds). Mirrors the Solana min-delegation chain: the values are
    /// validation/display inputs, never signing inputs, so serving a stale or
    /// seeded snapshot is safe while failing the caller is not. The only error
    /// that escapes is `CancellationError` — the caller is tearing down, and
    /// a seeded value must not mask the cancel.
    func fetchReserveValues() async throws -> RippleReserveValues? {
        // Resolve the host once so the cache key and the fetch always agree —
        // a custom-RPC change landing between two resolutions must not store
        // one host's reserves under another host's key.
        let host = resolvedHost
        do {
            return try await reserveValuesCache.value(
                for: Self.reserveValuesCacheKey(for: host),
                now: Date(),
                ttl: Self.reserveValuesTTL
            ) { [weak self] in
                guard let self else {
                    throw HelperError.runtimeError("RippleService deallocated")
                }
                let ledger = try await self.fetchServerState(host: host)?.result?.state?.validatedLedger
                // A server that is up but still syncing answers HTTP 200 with
                // `validated_ledger == null`, so both reserve fields come back
                // nil. Caching that fully-empty response would pin the seeds for
                // the whole 24h TTL and never refetch, even after the node
                // recovers. Throw instead so TTLCache keeps serving the last-good
                // snapshot (or the caller seeds) and retries next time — a thrown
                // error is not cached. A partial response with at least one real
                // field is still worth caching, seeds filling the gap.
                guard ledger?.reserveBase != nil || ledger?.reserveInc != nil else {
                    throw HelperError.runtimeError("server_state returned no reserve values (validated_ledger unavailable)")
                }
                return RippleReserveValues(reserveBase: ledger?.reserveBase, reserveInc: ledger?.reserveInc)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("fetchReserveValues: no live or cached values, seeding defaults: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pre-ceremony guard for the destination account: an XRPL Payment that
    /// would create the destination with less than the base reserve is
    /// rejected on-chain (`tecNO_DST_INSUF_XRP`) — after the ceremony, with
    /// the fee burned. Throws `RippleSendError.destinationNotActivated` when
    /// the destination is unfunded (a definitive `actNotFound`) and
    /// `amountDrops` is below the live base reserve.
    ///
    /// The block fires ONLY on proof the destination is unfunded. A transport
    /// or RPC error (offline, timeout, 429/5xx, an exhausted node-error retry)
    /// is NOT such proof: before this guard existed the same send to a funded
    /// address proceeded, so a transient lookup failure must not start blocking
    /// it — fail open and let the on-chain guard remain the backstop. Only a
    /// successful-but-uninterpretable response (HTTP 200, no account data, no
    /// `actNotFound`) fails closed, with a localized message.
    func validateDestinationActivation(address: String, amountDrops: BigInt) async throws {
        let result: RippleAccountResponse.Result?
        do {
            result = try await fetchAccountsInfo(for: address)?.result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Transport/RPC error — not evidence the destination is unfunded.
            // Don't gate an otherwise-valid send behind a fresh, uncached
            // account_info call whose transient failure would block it.
            logger.warning("validateDestinationActivation: destination lookup failed, allowing send: \(error.localizedDescription)")
            return
        }

        guard result?.accountData == nil else {
            return // Funded destination — any amount is valid.
        }

        // No account data: only a definitive `actNotFound` proves the account
        // is unfunded. Any other account_data-less-but-successful shape (a
        // proxy error page decoding to all-nils, an unexpected token) is
        // unverifiable, so fail closed with a localized message.
        guard result?.error == "actNotFound" else {
            throw RippleSendError.destinationLookupFailed(code: result?.error ?? "unknown")
        }

        // The destination does not exist yet, so the payment must fund at
        // least the base reserve. OwnerCount is 0 by definition for an
        // account being created.
        let reserveValues = try await fetchReserveValues()
        let baseReserve = RippleReserve.reservedDrops(
            ownerCount: 0,
            reserveBase: reserveValues?.reserveBase,
            reserveInc: reserveValues?.reserveInc
        )
        if amountDrops < baseReserve {
            throw RippleSendError.destinationNotActivated(
                minimumXRP: RippleReserve.minimumActivationXRP(baseReserveDrops: baseReserve)
            )
        }
    }

    /// Non-throwing, send-form reserve check for a native XRP payment. Reuses
    /// the same `account_info` lookup and `RippleReserve.reservedDrops(
    /// ownerCount: 0, …)` as `validateDestinationActivation`, so the form's
    /// minimum can never diverge from the Verify guard's. The funded/unfunded
    /// verdict is cached per destination address; amount edits reuse it without
    /// touching the node. Fails open: any lookup it can't complete returns
    /// `.unknown` (no inline error) — the Verify guard is the fail-closed
    /// backstop.
    /// - Parameter forceRefresh: bypass the cached funding verdict and re-query
    ///   `account_info` live. The while-typing path leaves this `false` (the
    ///   cache spares the node on every keystroke); the Continue-time block
    ///   passes `true` so its decision is always live and can never diverge
    ///   from the Verify guard — e.g. a destination that funds mid-session must
    ///   not stay blocked on a stale `.unfunded` verdict.
    func destinationReserveShortfall(
        address: String,
        amountDrops: BigInt,
        forceRefresh: Bool = false
    ) async -> RippleReserveCheck {
        let host = resolvedHost
        let key = Self.destinationFundingCacheKey(for: host, address: address)
        let now = Date()

        let funding: RippleDestinationFunding
        if !forceRefresh, let cached = await destinationFundingCache.cached(key, now: now, ttl: Self.destinationFundingTTL) {
            funding = cached
        } else {
            do {
                // Pin the lookup to the captured host so the verdict is stored
                // under the same host-scoped key it was fetched from, even if a
                // custom-RPC override changes mid-call.
                let result = try await fetchAccountsInfo(for: address, host: host)?.result
                if result?.accountData != nil {
                    funding = .funded
                } else if result?.error == "actNotFound" {
                    funding = .unfunded
                } else {
                    // Any other account_data-less shape (rate limit, proxy
                    // error page, malformed address) is unverifiable — fail
                    // open, and do not cache, so a later attempt can retry.
                    return .unknown
                }
                await destinationFundingCache.store(key, value: funding, at: now)
            } catch {
                // Transport failure — fail open, uncached (retryable).
                return .unknown
            }
        }

        switch funding {
        case .funded:
            return .satisfied
        case .unfunded:
            // OwnerCount is 0 by definition for an account being created; the
            // base reserve comes from the same live → cache → seed chain the
            // Verify guard uses, flattened to a non-throwing read here.
            let reserveValues = (try? await fetchReserveValues()) ?? nil
            let baseReserve = RippleReserve.reservedDrops(
                ownerCount: 0,
                reserveBase: reserveValues?.reserveBase,
                reserveInc: reserveValues?.reserveInc
            )
            guard amountDrops < baseReserve else { return .satisfied }
            return .belowMinimum(minimumXRP: RippleReserve.minimumActivationXRP(baseReserveDrops: baseReserve))
        }
    }

    /// Resolves the fee (in drops) for an XRPL Payment.
    ///
    /// The XRPL reference fee is 10 drops; servers escalate it under load via
    /// `load_factor / load_base`. We compute the current open-ledger cost and
    /// apply a safety multiplier so the transaction survives fee escalation
    /// during the (up to 5 min) TSS signing window, then clamp to a sane
    /// ceiling. Any failure falls back to that ceiling so a send is never
    /// blocked on the fee lookup.
    func fetchFee() async -> BigInt {
        do {
            let state = try await fetchServerState()?.result?.state
            return RippleFee.recommendedFee(
                baseFee: state?.validatedLedger?.baseFee,
                loadFactor: state?.loadFactor,
                loadBase: state?.loadBase
            )
        } catch {
            logger.error("fetchFee: falling back to ceiling: \(error.localizedDescription)")
            return BigInt(RippleFee.maxFeeDrops)
        }
    }

    /// Fetches `server_state`, optionally pinned to an explicit `host` so a
    /// caller can keep one request consistent with other host-derived state
    /// (e.g. the reserve cache key); `nil` resolves the override-aware host
    /// per request as usual.
    func fetchServerState(host: URL? = nil) async throws -> RippleServerStateResponse? {
        do {
            // Keep the explicit `host` (for reserve-cache-key consistency) and
            // route through the retrier so a transient node error on the pool
            // is retried against a healthy backend, same as the other reads.
            return try await retrier.request(
                RippleAPI(.serverState, host: host ?? resolvedHost),
                responseType: RippleServerStateResponse.self
            )
        } catch {
            logger.error("fetchServerState: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetches `account_info`, optionally pinned to an explicit `host` so a
    /// caller can keep one request consistent with other host-derived state
    /// (e.g. a host-scoped cache key); `nil` resolves the override-aware host
    /// per request as usual, matching `fetchServerState(host:)`.
    func fetchAccountsInfo(for walletAddress: String, host: URL? = nil) async throws -> RippleAccountResponse? {
        do {
            // Keep the explicit host (for the funding-cache key) and route
            // through the retrier so a transient node error is retried against a
            // healthy backend, matching fetchServerState(host:).
            return try await retrier.request(
                RippleAPI(.accountInfo(account: walletAddress), host: host ?? resolvedHost),
                responseType: RippleAccountResponse.self
            )
        } catch {
            logger.error("fetchAccountsInfo: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Destination-tag requirement (RequireDest)

    /// AccountRoot `lsfRequireDestTag` flag: the account refuses payments
    /// without a destination tag. Reference: xrpl.org AccountRoot flags.
    static let lsfRequireDestTag = 0x00020000

    /// Maps an `account_info` result onto a destination-tag requirement.
    /// Pure so tests can pin the classification without the network.
    static func classifyDestinationTagRequirement(result: RippleAccountResponse.Result?) -> RippleDestinationTagRequirement {
        if result?.error == "actNotFound" {
            // Unfunded destination: no AccountRoot exists, so it cannot set
            // the flag. (Whether the send can fund it is the reserve
            // check's concern, not this gate's.)
            return .accountNotFound
        }
        guard let flags = result?.accountData?.flags else {
            return .unknown
        }
        return (flags & lsfRequireDestTag) != 0 ? .required : .notRequired
    }

    /// Looks up whether `address` requires a destination tag. Never throws:
    /// lookup failures classify as `.unknown` so the caller can decide the
    /// fail-open/fail-closed posture explicitly.
    func fetchDestinationTagRequirement(for address: String) async -> RippleDestinationTagRequirement {
        do {
            let response = try await fetchAccountsInfo(for: address)
            return Self.classifyDestinationTagRequirement(result: response?.result)
        } catch {
            logger.error("fetchDestinationTagRequirement: \(error.localizedDescription)")
            return .unknown
        }
    }
}

/// Whether an XRPL destination requires a destination tag on incoming
/// payments (AccountRoot `lsfRequireDestTag`).
enum RippleDestinationTagRequirement: Equatable {
    case required
    case notRequired
    /// Destination account doesn't exist on-ledger (`actNotFound`).
    case accountNotFound
    /// Lookup failed or returned an unrecognized shape.
    case unknown
}

enum RippleSendError: Error, LocalizedError {
    /// The destination account does not exist and the amount is below the
    /// base reserve needed to create it. Carries the minimum in whole XRP,
    /// ready for user-facing copy.
    case destinationNotActivated(minimumXRP: String)
    /// `account_info` answered without account data and without a definitive
    /// `actNotFound` — the destination cannot be verified, so the send is
    /// blocked (fail closed). Technical copy, same style as
    /// `RippleBroadcastError`.
    case destinationLookupFailed(code: String)

    var errorDescription: String? {
        switch self {
        case .destinationNotActivated(let minimumXRP):
            return String(format: "xrpDestinationNotActivatedError".localized, minimumXRP)
        case .destinationLookupFailed(let code):
            return String(format: "xrpDestinationLookupFailedError".localized, code)
        }
    }
}

enum RippleBroadcastError: Error, LocalizedError {
    case broadcastFailed(code: String, message: String?)

    var errorDescription: String? {
        switch self {
        case let .broadcastFailed(code, message):
            if let message, !message.isEmpty {
                return "Ripple broadcast failed (\(code)): \(message)"
            }
            return "Ripple broadcast failed (\(code))"
        }
    }
}

struct RippleAccountResponse: Codable {
    let result: Result?

    struct Result: Codable {
        let accountData: AccountData?
        let ledgerCurrentIndex: Int?
        let queueData: QueueData?
        let status: String?
        let validated: Bool?
        /// rippled error token returned in an HTTP-200 error body. Two uses:
        /// `actNotFound` marks a non-existent (unfunded) account — a valid
        /// lookup outcome, intentionally not retryable — while node-level
        /// tokens (e.g. `amendmentBlocked`) drive the transient-error retry.
        let error: String?

        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
            case queueData = "queue_data"
            case status
            case validated
            case error
        }
    }

    struct AccountData: Codable {
        let account: String?
        let balance: String?
        let flags: Int?
        let ledgerEntryType: String?
        let ownerCount: Int?
        let previousTxnID: String?
        let previousTxnLgrSeq: Int?
        let sequence: Int?
        let index: String?

        enum CodingKeys: String, CodingKey {
            case account = "Account"
            case balance = "Balance"
            case flags = "Flags"
            case ledgerEntryType = "LedgerEntryType"
            case ownerCount = "OwnerCount"
            case previousTxnID = "PreviousTxnID"
            case previousTxnLgrSeq = "PreviousTxnLgrSeq"
            case sequence = "Sequence"
            case index
        }
    }

    struct QueueData: Codable {
        let authChangeQueued: Bool?
        let highestSequence: Int?
        let lowestSequence: Int?
        let maxSpendDropsTotal: String?
        let transactions: [Transaction]?
        let txnCount: Int?

        enum CodingKeys: String, CodingKey {
            case authChangeQueued = "auth_change_queued"
            case highestSequence = "highest_sequence"
            case lowestSequence = "lowest_sequence"
            case maxSpendDropsTotal = "max_spend_drops_total"
            case transactions
            case txnCount = "txn_count"
        }
    }

    struct Transaction: Codable {
        let authChange: Bool?
        let fee: String?
        let feeLevel: String?
        let maxSpendDrops: String?
        let seq: Int?
        let lastLedgerSequence: Int?

        enum CodingKeys: String, CodingKey {
            case authChange = "auth_change"
            case fee
            case feeLevel = "fee_level"
            case maxSpendDrops = "max_spend_drops"
            case seq
            case lastLedgerSequence = "LastLedgerSequence"
        }
    }
}

struct RippleServerStateResponse: Codable {
    let result: Result?

    struct Result: Codable {
        let state: State?
        /// Node-level error (e.g. `amendmentBlocked`) returned in an HTTP-200
        /// body when the backend can't serve `server_state`.
        let error: String?

        enum CodingKeys: String, CodingKey {
            case state
            case error
        }
    }

    struct State: Codable {
        let loadBase: Int?
        let loadFactor: Int?
        let validatedLedger: ValidatedLedger?

        enum CodingKeys: String, CodingKey {
            case loadBase = "load_base"
            case loadFactor = "load_factor"
            case validatedLedger = "validated_ledger"
        }
    }

    struct ValidatedLedger: Codable {
        let baseFee: Int?
        let reserveBase: Int?
        let reserveInc: Int?

        enum CodingKeys: String, CodingKey {
            case baseFee = "base_fee"
            case reserveBase = "reserve_base"
            case reserveInc = "reserve_inc"
        }
    }
}

extension RippleAccountResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}

extension RippleServerStateResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}
