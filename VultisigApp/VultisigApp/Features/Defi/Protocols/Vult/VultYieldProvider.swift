//
//  VultYieldProvider.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "vult-yield-provider")

/// Conforms the sVULT staking wrapper to `DefiYieldProvider`.
///
/// sVULT is a direct-EOA governance wrapper (no APY, no rewards): `depositFor`
/// (stake), `requestUnstake` (burn active sVULT into a cooldown escrow), `claim`
/// (collect after maturity), and `cancelUnstake` (restore) are ordinary contract
/// calls (`to = sVULT, value = 0, data = calldata`). Like the shared yield deposit path, the signed
/// `KeysignPayload` carries the calldata in `memo` on the chain's NATIVE coin so
/// the EVM signer forwards `memo → tx.data`.
///
/// Pending requests are enumerated locally (iOS has no `eth_getLogs`): the
/// `requestId` is captured from the `UnstakeRequested` log in our own
/// `requestUnstake` receipt, persisted, then each id is refreshed via
/// `getUnstakeRequest` / `isClaimable`. The persisted list is authoritative.
struct VultYieldProvider: DefiYieldProvider {
    let id: DefiYieldProviderID = .vult

    private let service = VultService.shared
    private let reads: VultReadService
    private let storage = YieldPositionStorageService()

    init(reads: VultReadService = .shared) {
        self.reads = reads
    }

    var chain: Chain { VultConstants.chain }
    var assetContract: String { VultConstants.underlyingVult }
    var requiresAccountSetup: Bool { false }
    var depositsEnabled: Bool { true }
    var hasWindowedRedemption: Bool { true }
    var assetDecimals: Int { VultConstants.assetDecimals }
    var depositRecipient: String { VultConstants.stakedVult }

    var presentation: YieldPresentation {
        YieldPresentation(
            titleKey: "vultStakeTitle",
            dashboardTitleKey: "vultStaked",
            dashboardDescriptionKey: "vultStakeDescription",
            depositedLabelKey: "vultStakedLabel",
            depositButtonKey: "vultStake",
            withdrawButtonKey: "vultRequestUnstake",
            depositTitleKey: "vultStakeTitle",
            withdrawTitleKey: "vultUnstakeTitle",
            withdrawAmountLabelKey: "vultUnstakeAmountLabel",
            withdrawBalanceAvailableKey: "vultStakedAvailable",
            withdrawConfirmKey: "vultRequestUnstake",
            ethRequiredKey: "vultStakeETHRequired",
            ethereumRequiredTitleKey: "vultEthereumRequired",
            ethereumRequiredDescriptionKey: "vultEthereumRequiredDescription",
            apyLabelKey: "vultStakeAPYLabel",
            sharesTicker: VultConstants.sharesTicker,
            showsRedemptionRows: true,
            staticApyText: nil,
            providerNameKey: "vultStakeProviderName",
            bannerLogoAsset: "vult",
            infoBannerKey: "vultStakeInfoText",
            rowLogoAsset: "vult",
            rowTitleKey: "vultStakeRowTitle",
            rowSubtitleKey: "vultStakeRowSubtitle",
            assetTicker: VultConstants.underlyingTicker,
            assetLogoAsset: "vult",
            nextRedemptionLabelKey: "vultCooldownLabel",
            sharesTickerLabelKey: "vultSharesTickerLabel",
            redemptionWindowNoteKey: "vultCooldownNote",
            redemptionPendingKey: "vultUnstakePending",
            redemptionClaimableKey: "vultUnstakeClaimable",
            claimAmountKey: "vultClaimAmount",
            claimAvailableInDaysKey: "vultClaimAvailableInDays",
            usesComputedSettlementWindow: false,
            supportsCancel: true,
            cancelRequestKey: "vultCancelRequestAmount"
        )
    }

    // MARK: - Account lifecycle (no-op — direct EOA)

    // swiftlint:disable async_without_await

    func resolveAccountAddress(vault: Vault) async throws -> String? {
        userAddress(vault: vault)
    }

    func createAccount(vault: Vault) async throws -> String {
        guard let address = userAddress(vault: vault) else {
            throw VultServiceError.missingCoin("No Ethereum address in vault")
        }
        return address
    }

    // swiftlint:enable async_without_await

    // MARK: - Reads

    // sVULT has no APY/TVL (it's a governance wrapper, not a yield vault). The
    // shared screen renders "--" for APY when `staticApyText`/`apy` are nil.
    // swiftlint:disable unused_parameter async_without_await
    func apy(vault: Vault) async throws -> Decimal? { nil }

    func tvl() async throws -> Decimal? { nil }
    // swiftlint:enable unused_parameter async_without_await

    // Instant `withdrawTo` is only valid when the cooldown is 0 (the contract
    // reverts `CooldownActive()` otherwise). Reading the live value future-proofs
    // the rare owner-sets-cooldown-to-0 case; today it resolves to `false`.
    // swiftlint:disable:next unused_parameter
    func canWithdrawInstantly(vault: Vault, amount: BigInt) async -> Bool {
        do {
            return try await reads.cooldownDuration() == .zero
        } catch {
            logger.error("VULT cooldownDuration read failed, defaulting to queued unstake: \(error.localizedDescription)")
            return false
        }
    }

    /// Refreshes the position WITHOUT re-enumerating redemptions from chain (iOS
    /// has no `eth_getLogs`). Reads `balanceOf` for the active stake, then refreshes
    /// each *locally persisted* request id via `getUnstakeRequest` + `isClaimable`,
    /// pruning ids the contract reports as settled/cancelled (`owner == 0` /
    /// `amount == 0`). The persisted list is the source of truth for *which*
    /// requests exist.
    func refreshPosition(vault: Vault) async throws -> YieldVaultPosition {
        guard let user = userAddress(vault: vault) else {
            return .empty()
        }

        let staked = try await reads.balanceOf(user: user)
        let depositedBalance = Self.humanAmount(staked)
        let nativeGas = nativeGasBalance(vault: vault)

        let persisted = try await MainActor.run { storage.redemptions(for: vault, providerID: id) }
        let refreshed = await refreshRedemptions(persisted)

        try await MainActor.run {
            try storage.replaceRedemptions(
                refreshed,
                providerID: id,
                depositedBalance: depositedBalance,
                nativeGasBalance: nativeGas,
                for: vault
            )
        }

        return YieldVaultPosition(
            depositedBalance: depositedBalance,
            nativeGasBalance: nativeGas,
            redemptions: refreshed,
            lastUpdated: .now
        )
    }

    /// Re-reads each persisted request on-chain, deriving its current status and
    /// maturity. A request whose `getUnstakeRequest` read fails is *kept* with its
    /// cached state (fail closed — never drop a real pending request on a transient
    /// read error); a request the contract reports empty is pruned.
    private func refreshRedemptions(_ persisted: [YieldRedemption]) async -> [YieldRedemption] {
        var result: [YieldRedemption] = []
        for redemption in persisted {
            guard let requestId = BigInt(redemption.id) else {
                logger.error("Persisted VULT redemption has non-numeric id \(redemption.id); keeping as-is")
                result.append(redemption)
                continue
            }
            do {
                let request = try await reads.getUnstakeRequest(requestId: requestId)
                if request.isEmpty {
                    logger.info("Pruning settled/cancelled VULT request \(redemption.id)")
                    continue
                }
                let claimable = (try? await reads.isClaimable(requestId: requestId)) ?? false
                result.append(
                    YieldRedemption(
                        id: redemption.id,
                        amount: Self.humanAmount(request.amount),
                        requestedAt: redemption.requestedAt,
                        claimableAt: Self.maturityDate(request.maturity),
                        status: claimable ? .claimable : .pending
                    )
                )
            } catch {
                logger.warning("VULT request \(redemption.id) refresh failed, keeping cached state: \(error.localizedDescription)")
                result.append(redemption)
            }
        }
        return result
    }

    // MARK: - Write builders

    /// Stake: a single keysign ceremony that, when the VULT allowance is short,
    /// signs `approve(sVULT, amount)` at nonce N then `depositFor(user, amount)` at
    /// N+1. The deposit is a native-coin EVM call (calldata in `memo`); the bundled
    /// `approvePayload` (token = VULT) is what makes the signer emit the approve and
    /// bump the deposit to N+1. When the allowance already covers `amount`, the
    /// approve is nil and this is a single deposit tx. Mirrors the shared deposit shim exactly —
    /// permit is deliberately NOT used.
    func buildDepositPayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload {
        guard let user = userAddress(vault: vault) else {
            throw VultServiceError.missingCoin("No Ethereum address in vault")
        }
        let depositData = try service.encodeDepositFor(account: user, amount: amount)

        let allowance = try await reads.allowance(owner: user)
        let approvePayload = Self.depositApprovePayload(allowance: allowance, amount: amount)
        let needsApprove = approvePayload != nil

        return try await makePayload(
            vault: vault,
            to: VultConstants.stakedVult,
            data: depositData,
            approvePayload: approvePayload,
            approvePending: needsApprove
        )
    }

    /// Request unstake: burns sVULT from the active balance into a cooldown escrow.
    /// `amount` arrives in VULT (== sVULT, 1:1) base units from the form.
    func buildRequestRedeemPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        _ = recipient
        let data = try service.encodeRequestUnstake(amount: amount)
        return try await makePayload(vault: vault, to: VultConstants.stakedVult, data: data)
    }

    /// Instant withdraw (`withdrawTo`) — only reachable when cooldown is 0. Today
    /// the contract reverts otherwise, so the withdraw form routes through
    /// `requestUnstake` via `canWithdrawInstantly == false`.
    func buildWithdrawPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        // Instant path is unreachable while cooldown != 0. Routing the unstake
        // request keeps a 0-cooldown future correct without a separate withdrawTo
        // encoder (escrow-then-claim still completes the unstake).
        try await buildRequestRedeemPayload(vault: vault, recipient: recipient, amount: amount)
    }

    /// Claim a matured request: returns the escrowed VULT to the vault's ETH
    /// address. Only a `.claimable` redemption may be claimed.
    func buildClaimPayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload {
        guard redemption.status == .claimable else {
            throw VultServiceError.keysignError("Only a claimable request can be claimed")
        }
        guard let requestId = BigInt(redemption.id) else {
            throw VultServiceError.keysignError("Invalid request id")
        }
        let data = try service.encodeClaim(requestId: requestId, receiver: recipient)
        return try await makePayload(vault: vault, to: VultConstants.stakedVult, data: data)
    }

    /// Cancel an in-flight request: restores the escrowed sVULT to the active
    /// balance. Valid for both pending and claimable (un-claimed) requests.
    func buildCancelUnstakePayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload {
        _ = recipient
        guard let requestId = BigInt(redemption.id) else {
            throw VultServiceError.keysignError("Invalid request id")
        }
        let data = try service.encodeCancelUnstake(requestId: requestId)
        return try await makePayload(vault: vault, to: VultConstants.stakedVult, data: data)
    }

    // MARK: - Pending-request capture (Decision 5)

    /// The ids of all locally persisted redemptions. Used by the reconciler to skip
    /// already-captured requests.
    @MainActor
    func persistedRedemptionIDs(vault: Vault) -> [String] {
        storage.redemptions(for: vault, providerID: id).map(\.id)
    }

    /// Persists a request captured by the reconciler (from a scanned receipt),
    /// carrying the current balance forward.
    @MainActor
    func persistCapturedRequest(_ redemption: YieldRedemption, vault: Vault) {
        let depositedBalance = storage.position(for: vault, providerID: id)?.depositedBalance ?? .zero
        let nativeGas = nativeGasBalance(vault: vault)
        persist(redemption, depositedBalance: depositedBalance, nativeGas: nativeGas, vault: vault)
    }

    @MainActor
    private func persist(_ redemption: YieldRedemption, depositedBalance: Decimal, nativeGas: Decimal, vault: Vault) {
        do {
            try storage.appendRedemption(
                redemption,
                providerID: id,
                depositedBalance: depositedBalance,
                nativeGasBalance: nativeGas,
                for: vault
            )
        } catch {
            logger.error("Failed to persist VULT redemption \(redemption.id): \(error.localizedDescription)")
        }
    }

    /// Removes a redemption record after a successful claim/cancel.
    @MainActor
    func removeRedemption(id redemptionID: String, vault: Vault) {
        guard let position = storage.position(for: vault, providerID: id) else { return }
        guard let record = position.redemptions.first(where: { $0.id == redemptionID }) else { return }
        Storage.shared.delete(record)
        try? Storage.shared.save()
    }

    // MARK: - Conversions

    /// `nil` when the amount can't be represented as base units (see `YieldAmount`).
    static func baseUnits(_ amount: Decimal) -> BigInt? {
        YieldAmount.baseUnits(amount, decimals: VultConstants.assetDecimals)
    }

    static func humanAmount(_ value: BigInt) -> Decimal {
        YieldAmount.humanAmount(value, decimals: VultConstants.assetDecimals)
    }

    /// Converts a Unix-seconds maturity into a `Date`, or `nil` for a zero/invalid
    /// timestamp (which the screen treats as "claimable now").
    static func maturityDate(_ maturity: BigInt) -> Date? {
        guard maturity > 0, let seconds = Double(exactly: NSDecimalNumber(string: maturity.description)) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Approve bundle

    /// The approve to bundle with a stake: `approve(sVULT, amount)` on the VULT
    /// token when the current allowance can't cover `amount`, else `nil`. `token`
    /// is VULT because the deposit keysign coin is the NATIVE coin (ETH), so the
    /// approve leg must explicitly target VULT. Pure so the gating is unit-testable.
    static func depositApprovePayload(allowance: BigInt, amount: BigInt) -> ERC20ApprovePayload? {
        guard allowance < amount else { return nil }
        return ERC20ApprovePayload(
            amount: amount,
            spender: VultConstants.stakedVult,
            token: VultConstants.underlyingVult
        )
    }

    // MARK: - Private

    private func userAddress(vault: Vault) -> String? {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }?.address
    }

    private func nativeGasBalance(vault: Vault) -> Decimal {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }?.balanceDecimal ?? .zero
    }

    /// Builds the EVM keysign payload for an sVULT contract call. The payload coin
    /// is the chain's NATIVE coin so the signer forwards `memo → tx.data`. An
    /// optional `approvePayload` (token = VULT) makes the signer emit a prior
    /// `approve` at nonce N and bump this call to N+1.
    private func makePayload(
        vault: Vault,
        to: String,
        data: Data,
        approvePayload: ERC20ApprovePayload? = nil,
        approvePending: Bool = false
    ) async throws -> KeysignPayload {
        guard let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw VultServiceError.missingCoin("Missing native coin for \(chain.name)")
        }

        let evmService = try EvmService.getService(forChain: chain)
        let sender = nativeCoin.address

        var dataHex = data.hexString
        if !dataHex.hasPrefix("0x") {
            dataHex = "0x" + dataHex
        }

        let (gasPrice, priorityFee, nonce) = try await evmService.getGasInfo(fromAddress: sender, mode: .fast)
        let gasLimit = try await gasLimit(
            service: evmService,
            sender: sender,
            to: to,
            dataHex: dataHex,
            approvePending: approvePending
        )

        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: gasPrice,
            priorityFeeWei: priorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )

        return try await KeysignPayloadFactory().buildTransfer(
            coin: nativeCoin,
            toAddress: to,
            amount: BigInt(0),
            memo: dataHex,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            approvePayload: approvePayload,
            vault: vault
        )
    }

    /// Gas limit for the call. When an approve is bundled, `eth_estimateGas` on the
    /// deposit reverts (VULT can't be pulled before the approve confirms), so use
    /// the EVM swap default; otherwise estimate, falling back to the same default.
    private func gasLimit(
        service: EvmService,
        sender: String,
        to: String,
        dataHex: String,
        approvePending: Bool
    ) async throws -> BigInt {
        let fallback = BigInt(EVMHelper.defaultETHSwapGasUnit)
        guard !approvePending else { return fallback }
        do {
            return try await service.estimateGasLimitForSwap(
                senderAddress: sender,
                toAddress: to,
                value: BigInt(0),
                data: dataHex
            )
        } catch {
            logger.warning("VULT gas estimate failed, using default: \(error.localizedDescription)")
            return fallback
        }
    }
}
