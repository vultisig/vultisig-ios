//
//  KaminoService.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog

protocol KaminoServiceProtocol: Sendable {
    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse
    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse
    /// Hydrates a curated vault with live state and metrics.
    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo
    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse]
    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse

    /// Builds an unsigned deposit transaction. The amount is in the vault's
    /// **underlying token**.
    ///
    /// Takes a descriptor rather than an address so the curated set is enforced
    /// by the type: an arbitrary vault string cannot reach Kamino through here.
    func buildDepositTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        amount: KaminoTokenAmount
    ) async throws -> String

    /// Builds an unsigned withdraw transaction. The amount is in **shares** —
    /// the inverse of deposit. This asymmetry is the API's, not ours.
    func buildWithdrawTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        shares: KaminoShareAmount
    ) async throws -> String
}

/// REST client for Kamino Earn vaults.
///
/// The service owns the boundary between Kamino's decimal-string JSON and the
/// app's typed amounts: nothing above it sees a raw numeric string, and a value
/// that fails the strict decimal rules throws rather than defaulting to zero.
struct KaminoService: KaminoServiceProtocol {

    private let httpClient: HTTPClientProtocol
    /// Shared, because the value that makes it worth having is one another
    /// `KaminoService` fetched. See `KaminoVaultInfoCache`.
    private let vaultInfoCache: KaminoVaultInfoCache
    private let logger = Log.defi.service

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        vaultInfoCache: KaminoVaultInfoCache = .shared
    ) {
        self.httpClient = httpClient
        self.vaultInfoCache = vaultInfoCache
    }

    // MARK: - Reads

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse {
        try await request(.vaultState(address: address), as: KaminoVaultStateResponse.self)
    }

    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse {
        try await request(.vaultMetrics(address: address), as: KaminoVaultMetricsResponse.self)
    }

    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] {
        try await request(.userPositions(owner: owner), as: [KaminoUserPositionResponse].self)
    }

    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse {
        try await request(.positionPnl(owner: owner, vault: vault), as: KaminoPnlResponse.self)
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        // The descriptor is what every later safety check is measured against, so
        // it has to be the registry's own entry and not merely something carrying
        // one of its addresses.
        guard KaminoVaultRegistry.descriptor(for: descriptor.address) == descriptor else {
            throw KaminoServiceError.vaultNotInRegistry(descriptor.address)
        }

        // Read AFTER that guard, never before it. Identity is decided by the
        // registry, and a cache hit must not become a way past the check that
        // decides it — the entry is keyed by an address, and an address is the
        // one part of a descriptor an attacker-supplied one would get right.
        if let cached = vaultInfoCache.value(for: descriptor.address) {
            return cached
        }

        async let stateTask = fetchVaultState(address: descriptor.address)
        async let metricsTask = fetchVaultMetrics(address: descriptor.address)
        let state = try await stateTask.state
        let metrics = try await metricsTask

        try Self.assertMatchesRegistry(state: state, descriptor: descriptor)

        guard let publishedMinDeposit = KaminoTokenAmount(
            baseUnitString: state.minDepositAmount,
            decimals: descriptor.tokenDecimals
        ) else {
            throw KaminoServiceError.malformedNumber(
                field: "minDepositAmount",
                value: state.minDepositAmount
            )
        }
        // The published figures are numbers a remote service hands us, and they
        // end up bounding what a user may spend. A non-positive or absurd one is
        // refused rather than propagated into a minimum nothing can satisfy.
        let minDeposit = Self.effectiveMinimumDeposit(published: publishedMinDeposit)
        guard publishedMinDeposit.isValidRequestAmount, minDeposit.isValidRequestAmount else {
            throw KaminoServiceError.malformedNumber(
                field: "minDepositAmount",
                value: state.minDepositAmount
            )
        }

        // TOKEN base units. The field's name suggests a share count and the two
        // scales differ on the SOL vault (9 vs 6), so reading it wrong is silent
        // — see `effectiveMinimumWithdraw` for how that was established.
        guard let publishedMinWithdraw = KaminoTokenAmount(
            baseUnitString: state.minWithdrawAmount,
            decimals: descriptor.tokenDecimals
        ) else {
            throw KaminoServiceError.malformedNumber(
                field: "minWithdrawAmount",
                value: state.minWithdrawAmount
            )
        }

        let apy30d = try Self.decimal(metrics.apy30d, field: "apy30d")
        let tokenPriceUsd = try Self.decimal(metrics.tokenPrice, field: "tokenPrice")

        // Parsed exactly rather than through `Decimal`: this rate converts a
        // user's token amount into the shares a withdraw burns.
        guard let tokensPerShare = KaminoRate(apiString: metrics.tokensPerShare),
              tokensPerShare.isPositive
        else {
            throw KaminoServiceError.malformedNumber(
                field: "tokensPerShare",
                value: metrics.tokensPerShare
            )
        }

        guard let minWithdraw = Self.effectiveMinimumWithdraw(
            published: publishedMinWithdraw,
            tokensPerShare: tokensPerShare,
            shareDecimals: descriptor.sharesDecimals
        ), publishedMinWithdraw.isValidRequestAmount, minWithdraw.isValidRequestAmount else {
            throw KaminoServiceError.malformedNumber(
                field: "minWithdrawAmount",
                value: state.minWithdrawAmount
            )
        }

        let info = KaminoVaultInfo(
            descriptor: descriptor,
            name: state.name,
            minDeposit: minDeposit,
            minWithdraw: minWithdraw,
            lookupTable: state.vaultLookupTable,
            apy30d: apy30d,
            tokensPerShare: tokensPerShare,
            tokenPriceUsd: tokenPriceUsd,
            // Advisory, so an unreadable value drops the liquidity notice rather
            // than failing the whole hydration and blocking deposits too.
            tokensAvailable: KaminoTokenAmount(
                decimalString: metrics.tokensAvailable,
                decimals: descriptor.tokenDecimals
            )
        )
        // Only a hydration that cleared every check above is stored. A response
        // that failed one throws, so nothing this refused can be served later.
        vaultInfoCache.store(info, for: descriptor.address)
        return info
    }

    /// The smallest deposit the form may offer.
    ///
    /// The published `minDepositAmount` is in the right unit — unlike its
    /// withdraw counterpart — but the program still refuses a deposit *at* it,
    /// with `DepositAmountBelowMinimum` (custom 7026,
    /// `vault_operations.rs:113`). Measured at one base unit of resolution:
    /// Steakhouse USDC refuses 100,007 and accepts 100,008 against a published
    /// 100,000; Allez SOL refuses 10,000,009 and accepts 10,000,010 against
    /// 10,000,000. So the shortfall is a handful of base units rather than the
    /// withdraw side's factor of two, and it moves with the share rate — the
    /// gap is a rounding loss in the share the deposit mints, not a second
    /// threshold.
    ///
    /// The margin is therefore proportional, with an absolute floor for a vault
    /// whose minimum is small enough that a tenth of a percent rounds away. Both
    /// bounds are generous against what was measured — 100 base units where 8
    /// were needed, 10,000 where 10 were — and both are invisible in money: a
    /// tenth of a percent of a ten-cent minimum.
    ///
    /// This also repairs the SOL vault's maximum. `maxNativeDepositLamports`
    /// probes with exactly this amount and the preparer requires the probe to
    /// simulate cleanly, so a probe below the program's floor made the whole
    /// measurement throw.
    private static func effectiveMinimumDeposit(published: KaminoTokenAmount) -> KaminoTokenAmount {
        let proportional = (published.baseUnits + minimumDepositMarginDivisor - 1) / minimumDepositMarginDivisor
        let margin = max(proportional, minimumDepositMarginFloor)
        return KaminoTokenAmount(
            baseUnits: published.baseUnits + margin,
            decimals: published.decimals
        )
    }

    /// A margin of one part in this many — a tenth of a percent.
    private static let minimumDepositMarginDivisor = BigInt(1_000)

    /// Smallest margin in base units, for a minimum too small for the
    /// proportional one to clear a rounding loss. Larger than either measured
    /// shortfall.
    private static let minimumDepositMarginFloor = BigInt(16)

    /// Multiple of the published minimum a withdraw's token value must reach.
    ///
    /// The measured floor sits just above two; the third is margin, because the
    /// rule below is a reading of observed behaviour rather than a documented
    /// contract.
    static let minimumWithdrawMultiple = BigInt(3)

    /// The smallest withdraw the form may offer, in SHARE base units.
    ///
    /// Deliberately **not** `state.minWithdrawAmount` converted, and that is the
    /// whole point of this function. Two things about that field were
    /// established by simulating the transactions the API builds, at one base
    /// unit of resolution:
    ///
    /// 1. **It is denominated in the underlying TOKEN, not in shares.** The
    ///    withdraw endpoint itself takes shares, which is what made the opposite
    ///    reading look right, and on the dollar vaults the rate is near 1 so the
    ///    two readings are within rounding of each other. On the SOL vault they
    ///    differ by a factor of about 930.
    /// 2. **The program's floor is higher than the published figure.** A
    ///    withdraw whose token value does not exceed twice the published amount
    ///    is refused on chain with `WithdrawAmountBelowMinimum`. Steakhouse USDC
    ///    refuses 1898 share base units (worth 2000.2 tokens) and accepts 1899
    ///    (2001.3); Allez SOL refuses 1861 (2000.9 lamports) and accepts 1862
    ///    (2002.0). Both withdraw shapes — the farm-staked one and the short one
    ///    — share the boundary, so it belongs to the vault withdraw and not to
    ///    the farm release.
    ///
    /// Read as shares, the published figure is roughly half of what the chain
    /// will accept, so the form advertised a minimum, accepted it, and then
    /// failed at the simulation gate with an error about an amount the user had
    /// been told was allowed. Nothing was ever at risk — that gate is what
    /// caught it — but the number on screen was wrong.
    ///
    /// Rounded up, because a share count worth fractionally less than the
    /// minimum is exactly the failure being fixed.
    private static func effectiveMinimumWithdraw(
        published: KaminoTokenAmount,
        tokensPerShare: KaminoRate,
        shareDecimals: Int
    ) -> KaminoShareAmount? {
        let required = KaminoTokenAmount(
            baseUnits: published.baseUnits * minimumWithdrawMultiple,
            decimals: published.decimals
        )
        return required.shareAmountRoundedUp(
            tokensPerShare: tokensPerShare,
            shareDecimals: shareDecimals
        )
    }

    /// Refuses a response whose account of the vault differs from the registry's.
    ///
    /// The mints, their decimals and the farm are immutable properties of a
    /// kVault, so this can never fire on a legitimate change. It exists because
    /// those values decide where funds go and how amounts are scaled: taking
    /// them from the API would mean validating a transaction the API built
    /// against values the same API supplied, and the pair could be made
    /// consistent. Checking here means the whole feature — not just the
    /// transaction validator — works from a vault identity the app already knew.
    private static func assertMatchesRegistry(
        state: KaminoVaultStateResponse.State,
        descriptor: KaminoVaultDescriptor
    ) throws {
        try assertEqual(state.tokenMint, descriptor.tokenMint, field: "tokenMint")
        try assertEqual(state.sharesMint, descriptor.sharesMint, field: "sharesMint")
        try assertEqual(
            String(state.tokenMintDecimals),
            String(descriptor.tokenDecimals),
            field: "tokenMintDecimals"
        )
        try assertEqual(
            String(state.sharesMintDecimals),
            String(descriptor.sharesDecimals),
            field: "sharesMintDecimals"
        )
        try assertEqual(farm(state.vaultFarm) ?? "", descriptor.farm ?? "", field: "vaultFarm")
    }

    private static func assertEqual(_ actual: String, _ expected: String, field: String) throws {
        guard actual == expected else {
            throw KaminoServiceError.vaultMetadataMismatch(field: field, expected: expected, actual: actual)
        }
    }

    // MARK: - Actions

    func buildDepositTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        amount: KaminoTokenAmount
    ) async throws -> String {
        try Self.assertCurated(vault)
        try Self.validate(amount, label: "deposit")
        let request = KaminoActionRequest(wallet: owner, kvault: vault.address, amount: amount.apiString)
        let response = try await self.request(.deposit(request: request), as: KaminoActionResponse.self)
        return response.transaction
    }

    func buildWithdrawTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        shares: KaminoShareAmount
    ) async throws -> String {
        try Self.assertCurated(vault)
        try Self.validate(shares, label: "withdraw")
        // `u64::MAX` is the API's own "withdraw everything" sentinel: it is what
        // a request AT OR ABOVE the user's balance is silently rewritten to. No
        // legitimate share balance is 18.4 quintillion base units, so refusing
        // the value outright costs nothing and closes the one way this app could
        // name it directly.
        //
        // It is not the only way to end up with one, though, and the other way
        // is upstream of here: asking for the whole balance produces the
        // sentinel in the RESPONSE. `KaminoSharePosition.spendable` is what
        // keeps every request this app makes strictly below the balance, and the
        // validator is what refuses the response if one arrives anyway.
        guard shares.baseUnits < KaminoBaseUnits.maxBaseUnits else {
            throw KaminoServiceError.invalidAmount(
                "withdraw amount \(shares.baseUnits) is the withdraw-everything sentinel"
            )
        }
        let request = KaminoActionRequest(wallet: owner, kvault: vault.address, amount: shares.apiString)
        let response = try await self.request(.withdraw(request: request), as: KaminoActionResponse.self)
        return response.transaction
    }

    /// Refuses to build against anything but the registry's own entry.
    ///
    /// The descriptor type narrows the parameter, but it is a struct with a
    /// memberwise initialiser — a caller can still assemble one that merely
    /// looks curated. Comparing against the registry entry is what makes the
    /// invariant hold, and it is the same check `fetchVaultInfo` runs: identity
    /// is decided here, not by whatever the API is willing to build.
    private static func assertCurated(_ descriptor: KaminoVaultDescriptor) throws {
        guard KaminoVaultRegistry.descriptor(for: descriptor.address) == descriptor else {
            throw KaminoServiceError.vaultNotInRegistry(descriptor.address)
        }
    }

    // MARK: - Plumbing

    /// Issues the request and converts Kamino's structured 400 body into a typed
    /// error, so callers can branch on `code` (`KVAULT_NOT_FOUND`,
    /// `TRANSACTION_SIZE_ERROR`, …) instead of matching on message text.
    private func request<T: Decodable>(_ target: KaminoAPI, as type: T.Type) async throws -> T {
        do {
            // A timeout on a read is retried once; a build POST is not. See
            // `KaminoAPI.isIdempotentRead` for why the builder is excluded even
            // though it signs nothing.
            let response = target.isIdempotentRead
                ? try await httpClient.requestRetryingTimeout(target, responseType: type)
                : try await httpClient.request(target, responseType: type)
            return response.data
        } catch let error as HTTPError {
            guard case .statusCode(let status, let data) = error,
                  let data,
                  let decoded = try? JSONDecoder().decode(KaminoErrorResponse.self, from: data)
            else { throw error }

            logger.error(
                "kamino \(target.path, privacy: .public) failed \(status, privacy: .public): \(decoded.code ?? "-", privacy: .public)"
            )
            throw KaminoServiceError.api(status: status, code: decoded.code, message: decoded.message)
        }
    }

    private static func decimal(_ raw: String, field: String) throws -> Decimal {
        guard let value = KaminoDecimal.parse(raw) else {
            throw KaminoServiceError.malformedNumber(field: field, value: raw)
        }
        return value
    }

    /// Last gate before an amount becomes a request body. The API accepts
    /// anything it can parse — a below-minimum deposit builds a transaction that
    /// fails on-chain, and an over-sized withdraw is rewritten to `u64::MAX`,
    /// meaning withdraw everything — so bounds are enforced here.
    private static func validate(_ amount: some KaminoBaseUnitAmount, label: String) throws {
        guard amount.isValidRequestAmount else {
            throw KaminoServiceError.invalidAmount(
                "\(label) amount \(amount.baseUnits) at \(amount.decimals) decimals is out of range"
            )
        }
    }

    // The decimal scales index a `10^n` factor in every conversion, so they have
    // to be sane. They no longer need a runtime bound check here because they
    // come from the registry rather than the response — `KaminoVaultRegistryTests`
    // pins each one inside `0...KaminoBaseUnits.maxDecimals`.

    /// The Solana default/system address doubles as "no farm attached".
    private static func farm(_ address: String) -> String? {
        guard !address.isEmpty, address != Self.systemProgramAddress else { return nil }
        return address
    }

    private static let systemProgramAddress = "11111111111111111111111111111111"
}
