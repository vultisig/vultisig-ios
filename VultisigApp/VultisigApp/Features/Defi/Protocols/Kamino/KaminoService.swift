//
//  KaminoService.swift
//  VultisigApp
//

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
    private let logger = Log.defi.service

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
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

        async let stateTask = fetchVaultState(address: descriptor.address)
        async let metricsTask = fetchVaultMetrics(address: descriptor.address)
        let state = try await stateTask.state
        let metrics = try await metricsTask

        try Self.assertMatchesRegistry(state: state, descriptor: descriptor)

        guard let minDeposit = KaminoTokenAmount(
            baseUnitString: state.minDepositAmount,
            decimals: descriptor.tokenDecimals
        ) else {
            throw KaminoServiceError.malformedNumber(
                field: "minDepositAmount",
                value: state.minDepositAmount
            )
        }

        // Share base units, not token base units — the two decimal scales differ
        // on the SOL vault (9 vs 6).
        guard let minWithdraw = KaminoShareAmount(
            baseUnitString: state.minWithdrawAmount,
            decimals: descriptor.sharesDecimals
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

        return KaminoVaultInfo(
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
            return try await httpClient.request(target, responseType: type).data
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
