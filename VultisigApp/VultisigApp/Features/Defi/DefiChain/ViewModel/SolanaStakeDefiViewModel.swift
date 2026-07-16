//
//  SolanaStakeDefiViewModel.swift
//  VultisigApp
//
//  Backs the Solana stake segment on the DeFi tab. Unlike Cosmos's
//  per-validator delegation list, Solana staking is per-STAKE-ACCOUNT: a wallet
//  holds N stake accounts, each delegating to exactly one validator with its own
//  activation lifecycle. So this VM produces one `SolanaStakeAccountRow` per
//  account — NOT a coin-keyed `StakePosition` `@Model` — folding in the live
//  epoch (for activation/cooldown state), validator metadata (name/logo), and a
//  resolved APY.
//
//  Stake accounts are read live (never long-cached) so a just-submitted
//  delegate/unstake/withdraw is visible on the next refresh. After a signed
//  keysign the caller invokes `invalidateAndRefresh(...)`, which additionally
//  drops the short-lived epoch cache so the post-tx state derivation is exact.
//
//  Data-layer counterpart to the position-card UI in `SolanaStakeDefiView`.
//

import Foundation
import Combine
import OSLog

@MainActor
final class SolanaStakeDefiViewModel: ObservableObject {
    @Published private(set) var rows: [SolanaStakeAccountRow] = []
    @Published private(set) var totalStaked: Decimal = 0
    @Published private(set) var rentReserve: Decimal = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let vault: Vault
    private let stakingService: SolanaStakingServiceProtocol
    private let metadataProvider: ValidatorMetadataProvider
    private let apyResolver: SolanaStakingAPYResolverProtocol
    private let storage: DefiPositionsStorageService
    private let onInvalidateCaches: @Sendable () -> Void
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-stake-defi-vm"
    )

    init(
        vault: Vault,
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService.shared,
        metadataProvider: ValidatorMetadataProvider = StakewizValidatorMetadataProvider.shared,
        apyResolver: SolanaStakingAPYResolverProtocol = SolanaStakingAPYResolver(),
        storage: DefiPositionsStorageService = DefiPositionsStorageService(),
        onInvalidateCaches: @escaping @Sendable () -> Void = { SolanaService.shared.invalidateEpochInfoCache() }
    ) {
        self.vault = vault
        self.stakingService = stakingService
        self.metadataProvider = metadataProvider
        self.apyResolver = apyResolver
        self.storage = storage
        self.onInvalidateCaches = onInvalidateCaches
        seedFromPersistedSnapshot()
    }

    /// Cache-first paint: map the persisted Solana `StakePosition` snapshot into
    /// display rows and assign `rows` / `totalStaked` synchronously, BEFORE any
    /// network call, so a warm store renders the last-known accounts instantly
    /// (matching the persisted THOR/Maya/TON DeFi path). The seed rows carry no
    /// live `SolanaStakeAccount`, so their actions stay disabled until the live
    /// refresh — they are a display projection, never a signing source.
    private func seedFromPersistedSnapshot() {
        let seeded = vault.stakePositions
            .filter { $0.coin.chain == .solana }
            .compactMap { position -> SolanaStakeAccountRow? in
                guard let pubkey = position.stakeAccountPubkey, !pubkey.isEmpty else { return nil }
                let state = position.activationState
                    .flatMap(SolanaStakeActivationState.init(rawValue:)) ?? .active
                let name = position.poolName
                    ?? SolanaValidator.truncatedPubkey(position.validatorVotePubkey ?? pubkey)
                return SolanaStakeAccountRow(
                    stakeAccountPubkey: pubkey,
                    stakeAccount: nil,
                    validatorName: name,
                    validatorVotePubkey: position.validatorVotePubkey,
                    validatorLogoURL: nil,
                    delegatedAmount: position.amount,
                    rentReserve: 0,
                    activationState: state,
                    apyPercent: position.apr.map { Decimal($0) }
                )
            }
            .sorted { $0.delegatedAmount > $1.delegatedAmount }

        guard !seeded.isEmpty else { return }
        rows = seeded
        totalStaked = seeded.map(\.delegatedAmount).reduce(0, +)
    }

    /// Fans out the stake-account read (uncached), the live epoch, the cached
    /// validator set + inflation, and the rent reserve, then folds them into one
    /// row per stake account. Per-call failures degrade individually: a failed
    /// validator/metadata/inflation fetch renders rows with on-chain-only data
    /// and a nil APY rather than dropping the position.
    func refresh(owner: String, decimals: Int) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let stakeAccountsTask = fetchStakeAccounts(owner: owner)
        async let epochTask = fetchEpochInfo()
        async let validatorsTask = fetchValidators()
        async let inflationTask = fetchInflation()
        async let rentReserveTask = fetchRentReserve()

        let stakeAccountsResult = await stakeAccountsTask
        let epoch = await epochTask
        let validators = await validatorsTask
        let inflation = await inflationTask
        let reserveLamports = await rentReserveTask

        let divisor = pow(Decimal(10), decimals)
        rentReserve = Decimal(reserveLamports) / divisor

        // Cache-first discipline: ONLY replace the painted rows / rewrite the
        // snapshot when the stake-account read SUCCEEDED. A failed read keeps the
        // last-known seed so an RPC outage never blanks the user's positions —
        // mirroring `BalanceService.fetchStakedBalance(.solana)` returning `nil`
        // (not `0`) on failure. An empty SUCCESS, by contrast, is a real "no
        // accounts" state and is allowed to clear the rows.
        guard let stakeAccounts = stakeAccountsResult else {
            logger.warning("Stake-account read failed — keeping last-known rows for owner \(owner, privacy: .private)")
            return
        }

        let validatorsByVote = Dictionary(
            validators.map { ($0.votePubkey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let totalActivatedStake = validators
            .map { $0.activatedStake }
            .reduce(UInt64.zero, +)

        // Enrich validator metadata (name / logo / Stakewiz APY) for just the
        // vote accounts the user is delegated to. The provider never throws — an
        // outage yields an empty map and rows fall back to on-chain display.
        let votePubkeys = stakeAccounts.compactMap { $0.delegation?.votePubkey }
        let metadata = await metadataProvider.metadata(forVotePubkeys: votePubkeys)

        let currentEpoch = epoch?.epoch
        let liveRows = stakeAccounts.map { account in
            row(
                for: account,
                divisor: divisor,
                currentEpoch: currentEpoch,
                validatorsByVote: validatorsByVote,
                metadata: metadata,
                inflation: inflation,
                totalActivatedStake: totalActivatedStake
            )
        }
        .sorted { $0.delegatedAmount > $1.delegatedAmount }

        rows = liveRows
        totalStaked = liveRows.map(\.delegatedAmount).reduce(0, +)

        if liveRows.isEmpty {
            logger.info("No stake accounts for owner \(owner, privacy: .private)")
        }

        persistSnapshot(rows: liveRows)
    }

    /// Writes the just-refreshed rows back to the persisted Solana `StakePosition`
    /// snapshot (id-keyed + Solana-scoped delete-stale) so the next open paints
    /// cache-first. Called ONLY on a successful stake-account read — an empty
    /// list here clears withdrawn-away accounts; a failed read never reaches it.
    private func persistSnapshot(rows liveRows: [SolanaStakeAccountRow]) {
        guard let coinMeta = vault.nativeCoin(for: .solana)?.toCoinMeta() else { return }
        let snapshots = liveRows.map { row in
            StakePositionData(
                coin: coinMeta,
                type: .stake,
                amount: row.delegatedAmount,
                apr: row.apyPercent.map { NSDecimalNumber(decimal: $0).doubleValue },
                poolName: row.validatorName,
                stakeAccountPubkey: row.stakeAccountPubkey,
                validatorVotePubkey: row.validatorVotePubkey,
                activationState: row.activationState.rawValue
            )
        }
        do {
            try storage.upsert(solanaStake: snapshots, for: vault)
        } catch {
            logger.error("Failed to persist Solana stake snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Post-keysign refresh. Drops the short-lived epoch cache before re-reading
    /// so the activation/cooldown state reflects the just-submitted tx, then
    /// re-runs the row pipeline. Stake accounts are already uncached.
    func invalidateAndRefresh(owner: String, decimals: Int) async {
        onInvalidateCaches()
        await refresh(owner: owner, decimals: decimals)
    }

    /// Uncached single-account read used when Withdraw is tapped, before the
    /// Verify screen is built. This makes the amount the user reviews the exact
    /// current account balance rather than the earlier list snapshot.
    func fetchStakeAccount(address: String) async throws -> SolanaStakeAccount? {
        try await stakingService.fetchStakeAccount(address: address)
    }

    /// Best-effort background prime of the FULL validator set + its metadata so
    /// the validator picker opens warm. Both reads hit the process-wide shared
    /// service/provider caches, so this is safe to call on every Solana DeFi tab
    /// load — only the first cold open per TTL window pays the fetch; subsequent
    /// calls are cache hits. Fire-and-forget: it never blocks or replaces the
    /// stake rows.
    func warmValidatorMetadata() {
        Task { [stakingService, metadataProvider] in
            guard let validators = try? await stakingService.fetchValidators(), !validators.isEmpty else { return }
            _ = await metadataProvider.metadata(forVotePubkeys: validators.map(\.votePubkey))
        }
    }

    // MARK: - Row building

    private func row(
        for account: SolanaStakeAccount,
        divisor: Decimal,
        currentEpoch: UInt64?,
        validatorsByVote: [String: SolanaValidator],
        metadata: [String: ValidatorMetadata],
        inflation: Double?,
        totalActivatedStake: UInt64
    ) -> SolanaStakeAccountRow {
        let delegation = account.delegation
        let votePubkey = delegation?.votePubkey
        var validator = votePubkey.flatMap { validatorsByVote[$0] }
        if let votePubkey, let meta = metadata[votePubkey] {
            validator?.metadata = meta
        }

        let delegatedLamports = delegation?.stake ?? 0
        let delegatedAmount = Decimal(delegatedLamports) / divisor

        let state: SolanaStakeActivationState
        if let currentEpoch {
            state = account.activationState(currentEpoch: currentEpoch)
        } else {
            // No epoch read — assume active when delegated so the row still
            // renders; the next refresh corrects the state once epoch is back.
            state = delegation == nil ? .inactive : .active
        }

        let apy: Decimal? = validator.flatMap { validator in
            apyResolver.apy(
                for: validator,
                metadataAPY: validator.metadata.apyEstimate,
                inflationRate: inflation,
                totalActivatedStake: totalActivatedStake,
                totalSupplyLamports: nil
            )
        }

        let validatorName = validator?.displayName
            ?? votePubkey.map { SolanaValidator.truncatedPubkey($0) }
            ?? SolanaValidator.truncatedPubkey(account.pubkey)

        return SolanaStakeAccountRow(
            stakeAccountPubkey: account.pubkey,
            stakeAccount: account,
            validatorName: validatorName,
            validatorVotePubkey: votePubkey,
            validatorLogoURL: validator?.logoURL,
            delegatedAmount: delegatedAmount,
            rentReserve: Decimal(account.rentExemptReserve) / divisor,
            activationState: state,
            apyPercent: apy
        )
    }

    // MARK: - Fetches (each degrades to a quiet default on failure)

    /// Returns the live stake accounts, or `nil` when the read FAILED — the
    /// caller uses `nil` to keep the last-known snapshot rather than clobbering
    /// it with `[]`. An empty array is a genuine "no accounts" success.
    private func fetchStakeAccounts(owner: String) async -> [SolanaStakeAccount]? {
        do {
            return try await stakingService.fetchStakeAccounts(owner: owner)
        } catch {
            logger.error("Failed to fetch stake accounts: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return nil
        }
    }

    private func fetchEpochInfo() async -> SolanaEpochInfo? {
        do {
            return try await stakingService.fetchEpochInfo()
        } catch {
            logger.warning("Failed to fetch epoch info: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchValidators() async -> [SolanaValidator] {
        do {
            return try await stakingService.fetchValidators()
        } catch {
            logger.warning("Failed to fetch validators: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchInflation() async -> Double? {
        do {
            return try await stakingService.fetchInflationRate()
        } catch {
            logger.warning("Failed to fetch inflation: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchRentReserve() async -> UInt64 {
        do {
            return try await stakingService.fetchRentReserve()
        } catch {
            logger.warning("Failed to fetch rent reserve: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}

/// A single stake-account row in the Solana DeFi stake segment. One row per
/// stake account — a wallet can hold N. `validatorName` / `validatorLogoURL`
/// fall back to a truncated vote pubkey when the validator set / metadata
/// couldn't be enriched; `apyPercent` is nil when no source produced a positive
/// value (the view hides the APY row).
///
/// `stakeAccount` is the full live `SolanaStakeAccount` the row actions hand to
/// the `FunctionTransactionType.solana*` flows. It is OPTIONAL because a
/// cache-first SEED row (reconstructed from the persisted `StakePosition`
/// snapshot before the live refresh lands) carries no live account — it paints
/// and gates buttons via `stakeAccountPubkey` + `activationState`, but its
/// actions stay disabled (`isActionable == false`) until the live refresh
/// supplies the account. Signing never reads the seed projection.
struct SolanaStakeAccountRow: Identifiable, Equatable, Sendable {
    var id: String { stakeAccountPubkey }
    /// Stake-account address — always present (seed or live); drives `id` and
    /// the row's pubkey display.
    let stakeAccountPubkey: String
    /// Live on-chain account, or `nil` for a not-yet-refreshed seed row.
    let stakeAccount: SolanaStakeAccount?
    let validatorName: String
    let validatorVotePubkey: String?
    let validatorLogoURL: URL?
    /// Delegated SOL (human-decimal), 0 for an initialized-but-undelegated
    /// account.
    let delegatedAmount: Decimal
    /// Rent-exempt reserve held by the account (human-decimal SOL) — not part of
    /// the delegated stake; shown so the user understands the account's lamports.
    let rentReserve: Decimal
    let activationState: SolanaStakeActivationState
    /// Fractional APY (`0.067` = 6.7%), or `nil` to hide the row.
    let apyPercent: Decimal?

    /// `true` once a live `SolanaStakeAccount` backs the row — actions
    /// (Unstake/Withdraw) can only fire then, never from a seed projection.
    var isActionable: Bool { stakeAccount != nil }

    /// Whether the account can be unstaked (deactivated) — only an active or
    /// activating delegation; a deactivating/inactive one has nothing to cool
    /// down.
    var canUnstake: Bool { activationState == .active || activationState == .activating }

    /// Whether the cooled-down lamports can be withdrawn — only once fully
    /// inactive.
    var canWithdraw: Bool { activationState == .inactive }
}
