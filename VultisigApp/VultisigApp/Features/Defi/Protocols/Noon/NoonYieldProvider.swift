//
//  NoonYieldProvider.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "noon-yield-provider")

/// Conforms the Noon ERC-7540 chain layer to `DefiYieldProvider`.
///
/// Noon is a direct-EOA vault: deposit / requestRedeem / withdraw / approve are
/// ordinary contract calls (`to = contract, value = 0, data = calldata`). Like
/// Circle, the signed `KeysignPayload` carries the calldata in `memo` on the
/// chain's NATIVE coin so the EVM signer forwards `memo → tx.data` rather than
/// rebuilding it as an ERC-20 `transfer`. There is no MSCA `execute()` wrapper.
struct NoonYieldProvider: DefiYieldProvider {
    let id: DefiYieldProviderID = .noon

    private let service = NoonService.shared
    private let reads: NoonReadService
    private let api: NoonApiService
    private let storage = YieldPositionStorageService()

    init(
        reads: NoonReadService = .shared,
        api: NoonApiService = .shared
    ) {
        self.reads = reads
        self.api = api
    }

    var chain: Chain { NoonConstants.chain }
    var assetContract: String { NoonConstants.usdcMainnet }
    var requiresAccountSetup: Bool { false }
    var depositsEnabled: Bool { true }
    var hasWindowedRedemption: Bool { true }
    var assetDecimals: Int { NoonConstants.assetDecimals }
    var depositRecipient: String { NoonConstants.vaultAddress }

    var presentation: YieldPresentation {
        YieldPresentation(
            titleKey: "noonTitle",
            dashboardTitleKey: "noonDashboardTitle",
            dashboardDescriptionKey: "noonDashboardDescription",
            depositedLabelKey: "noonUSDCDeposited",
            depositButtonKey: "noonDeposit",
            withdrawButtonKey: "noonWithdraw",
            depositTitleKey: "noonDepositTitle",
            withdrawTitleKey: "noonWithdrawTitle",
            withdrawAmountLabelKey: "noonWithdrawAmountLabel",
            withdrawBalanceAvailableKey: "noonWithdrawBalanceAvailable",
            withdrawConfirmKey: "noonWithdrawConfirm",
            ethRequiredKey: "noonDashboardETHRequired",
            ethereumRequiredTitleKey: "noonEthereumRequired",
            ethereumRequiredDescriptionKey: "noonEthereumRequiredDescription",
            apyLabelKey: "noonAPYLabel",
            sharesTicker: "naccUSDC",
            showsRedemptionRows: true,
            staticApyText: nil,
            providerNameKey: "noonTitle",
            bannerLogoAsset: "noon-logo",
            infoBannerKey: "noonDashboardInfoText",
            apyTooltipTitleKey: "noonAPYTooltipTitle",
            apyTooltipBodyKey: "noonAPYTooltipBody",
            rewardsTooltipTitleKey: "noonRewardsTooltipTitle",
            rewardsTooltipBodyKey: "noonRewardsTooltipBody",
            overviewTooltipTitleKey: "noonOverviewTooltipTitle",
            overviewTooltipBodyKey: "noonOverviewTooltipBody"
        )
    }

    // MARK: - Account lifecycle (no-op — direct EOA)

    // swiftlint:disable async_without_await

    func resolveAccountAddress(vault: Vault) async throws -> String? {
        userAddress(vault: vault)
    }

    func createAccount(vault: Vault) async throws -> String {
        guard let address = userAddress(vault: vault) else {
            throw NoonServiceError.missingCoin("No Ethereum address in vault")
        }
        return address
    }

    // swiftlint:enable async_without_await

    // MARK: - Reads

    func refreshPosition(vault: Vault) async throws -> YieldVaultPosition {
        guard let user = userAddress(vault: vault) else {
            return .empty()
        }

        let position = try await reads.fetchPosition(user: user)
        let nativeGas = nativeGasBalance(vault: vault)

        let depositedBalance = Self.humanAmount(position.currentAssets, decimals: NoonConstants.assetDecimals)
        let redemptions = Self.deriveRedemptions(from: position)

        try await MainActor.run {
            try storage.upsert(
                providerID: id,
                depositedBalance: depositedBalance,
                nativeGasBalance: nativeGas,
                redemptions: redemptions,
                for: vault
            )
        }

        return YieldVaultPosition(
            depositedBalance: depositedBalance,
            nativeGasBalance: nativeGas,
            redemptions: redemptions,
            lastUpdated: .now
        )
    }

    // swiftlint:disable:next unused_parameter
    func apy(vault: Vault) async throws -> Decimal? {
        try await api.fetchApy()
    }

    func tvl() async throws -> Decimal? {
        try await api.fetchTvl()
    }

    func canWithdrawInstantly(vault: Vault, amount: BigInt) async -> Bool {
        guard let user = userAddress(vault: vault) else { return false }
        do {
            let maxWithdraw = try await reads.maxWithdraw(user: user)
            return maxWithdraw >= amount
        } catch {
            logger.error("Noon maxWithdraw read failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Write builders

    func buildApprovePayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload? {
        guard let user = userAddress(vault: vault) else {
            throw NoonServiceError.missingCoin("No Ethereum address in vault")
        }
        let allowance = try await reads.allowance(owner: user)
        guard allowance < amount else { return nil }

        let data = try service.encodeUsdcApprove(amount: amount)
        return try await makePayload(vault: vault, to: assetContract, data: data)
    }

    func buildDepositPayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload {
        guard let user = userAddress(vault: vault) else {
            throw NoonServiceError.missingCoin("No Ethereum address in vault")
        }
        let minimum = try await resolvedMinimum(fallback: NoonConstants.minDepositAssets)
        try service.assertDepositMinimum(assets: amount, minimum: minimum)

        let data = try service.encodeDeposit(assets: amount, receiver: user)
        return try await makePayload(vault: vault, to: NoonConstants.vaultAddress, data: data)
    }

    func buildRequestRedeemPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        let minimum = try await resolvedMinimum(fallback: NoonConstants.minRedeemShares)
        try service.assertRedeemMinimum(shares: amount, minimum: minimum)

        let data = try service.encodeRequestRedeem(shares: amount, receiver: recipient, owner: recipient)
        return try await makePayload(vault: vault, to: NoonConstants.vaultAddress, data: data)
    }

    func buildWithdrawPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        let data = try service.encodeWithdraw(assets: amount, receiver: recipient, owner: recipient)
        return try await makePayload(vault: vault, to: NoonConstants.vaultAddress, data: data)
    }

    func buildClaimPayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload {
        // Only a `.claimable` redemption may be claimed. A claimable row's `amount`
        // is in ASSET units, which is what `claimableAssets`/`encodeWithdraw`
        // expect; a `.pending` row's `amount` is in SHARE units, so converting it
        // through assetDecimals would build a wrong-denominator withdraw. (Today
        // assetDecimals == shareDecimals == 6 so the units coincide — this guards
        // the invariant against a future divergence.)
        guard redemption.status == .claimable else {
            throw NoonServiceError.keysignError("Only a claimable redemption can be claimed")
        }
        let assets = try await claimableAssets(vault: vault, fallback: redemption.amount)
        let data = try service.encodeWithdraw(assets: assets, receiver: recipient, owner: recipient)
        return try await makePayload(vault: vault, to: NoonConstants.vaultAddress, data: data)
    }

    /// Re-reads `maxWithdraw(user)` at claim time so yield that accrues between
    /// the position read and signing is included in the withdraw. Falls back to
    /// the redemption's cached amount if the read fails.
    private func claimableAssets(vault: Vault, fallback: Decimal) async throws -> BigInt {
        if let user = userAddress(vault: vault) {
            do {
                let fresh = try await reads.maxWithdraw(user: user)
                if fresh > 0 { return fresh }
            } catch {
                logger.warning("Noon claim maxWithdraw re-read failed, using cached amount: \(error.localizedDescription)")
            }
        }
        // Fail closed: never sign a zero-amount claim if the cached amount can't
        // be converted to base units.
        guard let fallbackUnits = Self.baseUnits(fallback, decimals: NoonConstants.assetDecimals) else {
            throw NoonServiceError.readError("Cannot resolve claimable amount")
        }
        return fallbackUnits
    }

    /// Converts a human-readable decimal amount into integer base units. `nil`
    /// when the amount can't be represented as base units (see `YieldAmount`).
    static func baseUnits(_ amount: Decimal, decimals: Int) -> BigInt? {
        YieldAmount.baseUnits(amount, decimals: decimals)
    }

    /// Converts integer base units into a human-readable decimal (the inverse of
    /// `baseUnits`), e.g. 97_617_839 / 10^6 = 97.617839.
    static func humanAmount(_ value: BigInt, decimals: Int) -> Decimal {
        YieldAmount.humanAmount(value, decimals: decimals)
    }

    // MARK: - Redemption state machine

    /// Maps the on-chain read snapshot to a redemption row. The settlement date
    /// is derived from the weekly window so the pending copy can show
    /// "claimable in ~N days".
    static func deriveRedemptions(from position: NoonVaultPosition) -> [YieldRedemption] {
        switch position.redemptionState {
        case .none:
            return []
        case .claimable:
            let amount = humanAmount(position.claimableAssets, decimals: NoonConstants.assetDecimals)
            guard amount > 0 || position.claimableRedeemShares > 0 else { return [] }
            return [
                YieldRedemption(
                    id: redemptionID(position: position),
                    amount: amount,
                    requestedAt: Date(),
                    claimableAt: nil,
                    status: .claimable
                )
            ]
        case .pending:
            let amount = humanAmount(position.pendingRedeemShares, decimals: NoonConstants.shareDecimals)
            return [
                YieldRedemption(
                    id: redemptionID(position: position),
                    amount: amount,
                    requestedAt: Date(),
                    claimableAt: nextSettlementDate(),
                    status: .pending
                )
            ]
        }
    }

    /// Next weekly settlement: the upcoming window close (Wed 23:00 UTC) plus the
    /// settlement window.
    static func nextSettlementDate(now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        calendar.timeZone = utc

        var components = DateComponents()
        components.weekday = NoonConstants.RedemptionWindow.closesWeekday
        components.hour = NoonConstants.RedemptionWindow.closesHourUtc
        components.minute = 0
        components.second = 0

        guard let nextClose = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) else { return nil }

        return calendar.date(
            byAdding: .day,
            value: NoonConstants.RedemptionWindow.settlementDays,
            to: nextClose
        )
    }

    private static func redemptionID(position: NoonVaultPosition) -> String {
        "noon_\(position.redemptionState.rawValue)"
    }

    // MARK: - Private

    private func userAddress(vault: Vault) -> String? {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }?.address
    }

    private func nativeGasBalance(vault: Vault) -> Decimal {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }?.balanceDecimal ?? .zero
    }

    private func resolvedMinimum(fallback: String) async throws -> BigInt {
        let fallbackValue = BigInt(fallback) ?? .zero
        do {
            let onChain = try await reads.minAmountWei()
            return onChain > 0 ? onChain : fallbackValue
        } catch {
            logger.warning("Noon MIN_AMOUNT_WEI read failed, using fallback: \(error.localizedDescription)")
            return fallbackValue
        }
    }

    /// Builds the EVM keysign payload for a Noon contract call. The payload coin
    /// is the chain's NATIVE coin so the signer forwards `memo → tx.data` rather
    /// than rebuilding an ERC-20 transfer (the #4484 pattern, applied to a
    /// direct-EOA call).
    private func makePayload(vault: Vault, to: String, data: Data) async throws -> KeysignPayload {
        guard let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw NoonServiceError.missingCoin("Missing native coin for \(chain.name)")
        }

        let service = try EvmService.getService(forChain: chain)
        let sender = nativeCoin.address

        var dataHex = data.hexString
        if !dataHex.hasPrefix("0x") {
            dataHex = "0x" + dataHex
        }

        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: sender, mode: .fast)
        let gasLimit = try await service.estimateGasLimitForSwap(
            senderAddress: sender,
            toAddress: to,
            value: BigInt(0),
            data: dataHex
        )

        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: gasPrice,
            priorityFeeWei: priorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )

        return KeysignPayload(
            coin: nativeCoin,
            toAddress: to,
            toAmount: BigInt(0),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: dataHex,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
