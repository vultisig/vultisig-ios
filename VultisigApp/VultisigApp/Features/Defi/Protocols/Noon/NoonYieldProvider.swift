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
            bannerLogoAsset: "noon-defi-banner",
            infoBannerKey: "noonDashboardInfoText"
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

    /// Builds the first-deposit payload: a single keysign ceremony that, when the
    /// USDC allowance is short, signs+broadcasts `approve(vault, amount)` at nonce
    /// N then `deposit(assets, receiver)` at nonce N+1. The deposit rides the
    /// generic-swap path (`SwapPayload.generic`) carrying the `deposit` call in
    /// `quote.tx`; the bundled `approvePayload` is what makes the existing signer
    /// emit two transactions (mirrors the THORChain LP-add construction). When the
    /// allowance already covers `amount`, `approvePayload` is nil and this is a
    /// single deposit transaction — still routed through `.generic`.
    func buildDepositPayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload {
        guard let user = userAddress(vault: vault) else {
            throw NoonServiceError.missingCoin("No Ethereum address in vault")
        }
        guard let usdcCoin = usdcCoin(vault: vault) else {
            throw NoonServiceError.missingCoin("Missing USDC coin for \(chain.name)")
        }
        let minimum = try await resolvedMinimum(fallback: NoonConstants.minDepositAssets)
        try service.assertDepositMinimum(assets: amount, minimum: minimum)

        // Deposit calldata stays byte-equal to the SDK golden vector — selector
        // 0x6e553f65, args [assets, receiver=user].
        let depositData = try service.encodeDeposit(assets: amount, receiver: user)

        // Only attach an approve when the current allowance can't cover the
        // deposit. With an approve present, the signer increments the deposit's
        // nonce and broadcasts approve→deposit; without it, this is a lone deposit.
        let allowance = try await reads.allowance(owner: user)
        let approvePayload = Self.depositApprovePayload(allowance: allowance, amount: amount)
        let needsApprove = approvePayload != nil

        return try await makeBundledDepositPayload(
            vault: vault,
            usdcCoin: usdcCoin,
            sender: user,
            depositData: depositData,
            depositAmount: amount,
            approvePayload: approvePayload,
            approvePending: needsApprove
        )
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

    /// The USDC ERC-20 coin on the vault chain. The bundled deposit signs from
    /// this coin so the approve targets USDC's contract (`coin.contractAddress`)
    /// and the deposit signs from the same EOA — both share the user's address.
    private func usdcCoin(vault: Vault) -> Coin? {
        vault.coins.first { $0.chain == chain && $0.ticker == "USDC" }
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

    /// Assembles the bundled approve+deposit payload. The deposit `deposit(...)`
    /// call is carried in `GenericSwapPayload.quote.tx` and signed by the existing
    /// `OneInchSwaps` generic-swap path; the optional `approvePayload` is what the
    /// signer turns into a prior `approve` at nonce N (the deposit then signs at
    /// nonce N+1). The keysign coin is USDC so the approve targets USDC's
    /// contract; the deposit's target is `quote.tx.to` (the vault) regardless.
    private func makeBundledDepositPayload(
        vault: Vault,
        usdcCoin: Coin,
        sender: String,
        depositData: Data,
        depositAmount: BigInt,
        approvePayload: ERC20ApprovePayload?,
        approvePending: Bool
    ) async throws -> KeysignPayload {
        let service = try EvmService.getService(forChain: chain)

        var depositDataHex = depositData.hexString
        if !depositDataHex.hasPrefix("0x") {
            depositDataHex = "0x" + depositDataHex
        }

        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: sender, mode: .fast)
        let gasLimit = try await depositGasLimit(
            service: service,
            sender: sender,
            depositDataHex: depositDataHex,
            approvePending: approvePending
        )

        let genericPayload = Self.makeGenericDepositPayload(
            usdcCoin: usdcCoin,
            sender: sender,
            depositDataHex: depositDataHex,
            depositAmount: depositAmount,
            gasPrice: gasPrice,
            gasLimit: gasLimit
        )

        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: gasPrice,
            priorityFeeWei: priorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )

        return try await KeysignPayloadFactory().buildTransfer(
            coin: usdcCoin,
            toAddress: NoonConstants.vaultAddress,
            amount: depositAmount,
            memo: nil,
            chainSpecific: chainSpecific,
            swapPayload: .generic(genericPayload),
            approvePayload: approvePayload,
            vault: vault
        )
    }

    /// The approve to bundle with a deposit: `approve(vault, amount)` when the
    /// current allowance can't cover `amount`, else `nil` (allowance already
    /// sufficient → single deposit tx). Pure so the gating is unit-testable.
    static func depositApprovePayload(allowance: BigInt, amount: BigInt) -> ERC20ApprovePayload? {
        guard allowance < amount else { return nil }
        return ERC20ApprovePayload(amount: amount, spender: NoonConstants.vaultAddress)
    }

    /// Pure construction of the generic-swap payload that carries the deposit
    /// call. Kept side-effect-free (no RPC) so the calldata-in-quote invariant is
    /// unit-testable. Gas/gasPrice travel in `quote.tx` (no longer sourced from
    /// the verify screen) and are forced up to `chainSpecific` at sign time by
    /// `OneInchSwaps`.
    static func makeGenericDepositPayload(
        usdcCoin: Coin,
        sender: String,
        depositDataHex: String,
        depositAmount: BigInt,
        gasPrice: BigInt,
        gasLimit: BigInt
    ) -> GenericSwapPayload {
        let quoteTx = EVMQuote.Transaction(
            from: sender,
            to: NoonConstants.vaultAddress,
            data: depositDataHex,
            value: "0",
            gasPrice: String(gasPrice),
            gas: Int64(clamping: gasLimit)
        )
        return GenericSwapPayload(
            fromCoin: usdcCoin,
            toCoin: usdcCoin,
            fromAmount: depositAmount,
            toAmountDecimal: humanAmount(depositAmount, decimals: NoonConstants.assetDecimals),
            quote: EVMQuote(dstAmount: depositAmount.description, tx: quoteTx),
            provider: .oneInch
        )
    }

    /// Gas limit for the deposit leg. When an approve is bundled, `eth_estimateGas`
    /// on the deposit reverts (USDC can't be pulled before the approve confirms),
    /// so use the EVM swap default; otherwise estimate, falling back on the same
    /// default if the node call fails.
    private func depositGasLimit(
        service: EvmService,
        sender: String,
        depositDataHex: String,
        approvePending: Bool
    ) async throws -> BigInt {
        let fallback = BigInt(EVMHelper.defaultETHSwapGasUnit)
        guard !approvePending else { return fallback }
        do {
            return try await service.estimateGasLimitForSwap(
                senderAddress: sender,
                toAddress: NoonConstants.vaultAddress,
                value: BigInt(0),
                data: depositDataHex
            )
        } catch {
            logger.warning("Noon deposit gas estimate failed, using default: \(error.localizedDescription)")
            return fallback
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
