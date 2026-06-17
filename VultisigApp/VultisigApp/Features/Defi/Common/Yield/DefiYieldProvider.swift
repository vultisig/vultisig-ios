//
//  DefiYieldProvider.swift
//  VultisigApp
//

import Foundation
import BigInt

/// One value-type id per USDC-yield-vault provider. Drives the DeFi list, the
/// navigation route, and the persisted position key.
enum DefiYieldProviderID: String, Hashable, CaseIterable, Codable {
    case circle
    case vult
}

/// Read model for a single redemption. Instant redemptions have no settlement
/// wait (`claimableAt == nil`); windowed providers carry a claimable date.
struct YieldRedemption: Identifiable, Hashable {
    enum Status: String, Hashable {
        // swiftlint:disable:next discouraged_none_name
        case none
        case pending
        case claimable
        case settled
    }

    let id: String
    let amount: Decimal
    let requestedAt: Date
    /// `nil` ⇒ instant (no settlement wait).
    let claimableAt: Date?
    let status: Status

    var isClaimable: Bool {
        claimableAt.map { Date() >= $0 } ?? true
    }
}

/// Value snapshot of a vault position, passed across actor boundaries.
struct YieldVaultPosition: Hashable {
    let depositedBalance: Decimal
    let nativeGasBalance: Decimal
    let redemptions: [YieldRedemption]
    let lastUpdated: Date

    static func empty() -> YieldVaultPosition {
        YieldVaultPosition(depositedBalance: .zero, nativeGasBalance: .zero, redemptions: [], lastUpdated: .now)
    }
}

/// Provider-specific copy and display flags for the shared yield screens, so the
/// generic shells render each vault's labels per provider without branching on
/// the id. Strings are localization keys, resolved at the view via `.localized`.
struct YieldPresentation {
    /// Screen title for the dashboard / deposit / withdraw screens.
    let titleKey: String
    let dashboardTitleKey: String
    let dashboardDescriptionKey: String
    let depositedLabelKey: String
    let depositButtonKey: String
    let withdrawButtonKey: String
    let depositTitleKey: String
    let withdrawTitleKey: String
    let withdrawAmountLabelKey: String
    let withdrawBalanceAvailableKey: String
    let withdrawConfirmKey: String
    let ethRequiredKey: String
    let ethereumRequiredTitleKey: String
    let ethereumRequiredDescriptionKey: String
    /// Label for the APY row.
    let apyLabelKey: String
    /// Share-token ticker shown in the shares row, e.g. "naccUSDC".
    let sharesTicker: String
    /// Show the "Next redemption" + "Shares ticker" rows (windowed vaults only).
    let showsRedemptionRows: Bool
    /// Static APY string for vaults without a live feed (Circle "1%"); `nil`
    /// when the APY comes from the provider's feed.
    let staticApyText: String?

    // MARK: - Chrome (top banner / info banner)

    /// Provider name shown small/secondary at the top of the banner (e.g. "Circle").
    let providerNameKey: String
    /// Asset name for the badge logo shown (clipped to a circle) in the top banner.
    let bannerLogoAsset: String
    /// Closable info banner body shown on the empty/setup state.
    let infoBannerKey: String

    // MARK: - DeFi list row

    /// Logo asset for the DeFi-tab list row (circle-clipped).
    let rowLogoAsset: String
    /// Title shown in the DeFi-tab list row (e.g. "Circle").
    let rowTitleKey: String
    /// Optional secondary line under the row title (Circle's "Yield Account");
    /// `nil` hides it.
    let rowSubtitleKey: String?

    // MARK: - Account setup card (account-gated providers only)

    /// Label above the deposited balance on the "Open Account" setup card.
    let setupBalanceLabelKey: String
    /// Setup button title while the account is being created.
    let setupCreatingAccountKey: String
    /// Setup button title prompting the user to open an account.
    let setupOpenAccountKey: String

    // MARK: - Deposited-asset display (parameterized off the per-provider asset)

    /// Ticker of the deposited asset shown in amounts ("USDC" for Circle,
    /// "VULT" for staking). Drives the position-card and claim-button copy.
    let assetTicker: String
    /// Logo asset for the deposited-asset icon in the position/setup card
    /// ("usdc" for Circle, "vult" for staking).
    let assetLogoAsset: String

    // MARK: - Redemption section copy

    /// Label for the "Next redemption" info row (windowed vaults).
    let nextRedemptionLabelKey: String
    /// Label for the shares-ticker info row.
    let sharesTickerLabelKey: String
    /// Note shown when a windowed vault has a balance but no in-flight redemption
    /// (VULT's cooldown note).
    let redemptionWindowNoteKey: String
    /// Banner copy for a pending redemption.
    let redemptionPendingKey: String
    /// Banner copy for a claimable redemption.
    let redemptionClaimableKey: String
    /// Format string for the per-row Claim button title (one `%@` for the amount).
    let claimAmountKey: String
    /// Format string for "claimable in N days" (one `%d`).
    let claimAvailableInDaysKey: String

    // MARK: - Maturity source + cancel action (VULT extensions)

    /// When `true`, the "Next redemption" date comes from the provider's computed
    /// settlement window. When `false`, the screen reads each redemption's own
    /// on-chain `claimableAt` (VULT — per-request maturity).
    let usesComputedSettlementWindow: Bool
    /// When `true`, each pending redemption row shows a Cancel button (VULT's
    /// `cancelUnstake`). Default `false` — instant providers have no cancel action.
    let supportsCancel: Bool
    /// Format string for the per-row Cancel button title (one `%@` for the amount).
    let cancelRequestKey: String

    /// Memberwise initializer with defaults for the parameterized fields so the
    /// existing Circle call sites stay USDC-shaped without restating every new
    /// key; staking overrides the VULT-specific ones.
    init(
        titleKey: String,
        dashboardTitleKey: String,
        dashboardDescriptionKey: String,
        depositedLabelKey: String,
        depositButtonKey: String,
        withdrawButtonKey: String,
        depositTitleKey: String,
        withdrawTitleKey: String,
        withdrawAmountLabelKey: String,
        withdrawBalanceAvailableKey: String,
        withdrawConfirmKey: String,
        ethRequiredKey: String,
        ethereumRequiredTitleKey: String,
        ethereumRequiredDescriptionKey: String,
        apyLabelKey: String,
        sharesTicker: String,
        showsRedemptionRows: Bool,
        staticApyText: String?,
        providerNameKey: String,
        bannerLogoAsset: String,
        infoBannerKey: String,
        rowLogoAsset: String,
        rowTitleKey: String,
        rowSubtitleKey: String?,
        setupBalanceLabelKey: String = "circleSetupAccountBalance",
        setupCreatingAccountKey: String = "circleCreatingAccount",
        setupOpenAccountKey: String = "circleSetupOpenAccount",
        assetTicker: String = "USDC",
        assetLogoAsset: String = "usdc",
        nextRedemptionLabelKey: String = "yieldNextRedemption",
        sharesTickerLabelKey: String = "yieldSharesTicker",
        redemptionWindowNoteKey: String = "yieldRedemptionWindowNote",
        redemptionPendingKey: String = "yieldRedemptionPending",
        redemptionClaimableKey: String = "yieldRedemptionClaimable",
        claimAmountKey: String = "yieldClaimAmount",
        claimAvailableInDaysKey: String = "yieldClaimAvailableInDays",
        usesComputedSettlementWindow: Bool = true,
        supportsCancel: Bool = false,
        cancelRequestKey: String = "vultCancelRequestAmount"
    ) {
        self.titleKey = titleKey
        self.dashboardTitleKey = dashboardTitleKey
        self.dashboardDescriptionKey = dashboardDescriptionKey
        self.depositedLabelKey = depositedLabelKey
        self.depositButtonKey = depositButtonKey
        self.withdrawButtonKey = withdrawButtonKey
        self.depositTitleKey = depositTitleKey
        self.withdrawTitleKey = withdrawTitleKey
        self.withdrawAmountLabelKey = withdrawAmountLabelKey
        self.withdrawBalanceAvailableKey = withdrawBalanceAvailableKey
        self.withdrawConfirmKey = withdrawConfirmKey
        self.ethRequiredKey = ethRequiredKey
        self.ethereumRequiredTitleKey = ethereumRequiredTitleKey
        self.ethereumRequiredDescriptionKey = ethereumRequiredDescriptionKey
        self.apyLabelKey = apyLabelKey
        self.sharesTicker = sharesTicker
        self.showsRedemptionRows = showsRedemptionRows
        self.staticApyText = staticApyText
        self.providerNameKey = providerNameKey
        self.bannerLogoAsset = bannerLogoAsset
        self.infoBannerKey = infoBannerKey
        self.rowLogoAsset = rowLogoAsset
        self.rowTitleKey = rowTitleKey
        self.rowSubtitleKey = rowSubtitleKey
        self.setupBalanceLabelKey = setupBalanceLabelKey
        self.setupCreatingAccountKey = setupCreatingAccountKey
        self.setupOpenAccountKey = setupOpenAccountKey
        self.assetTicker = assetTicker
        self.assetLogoAsset = assetLogoAsset
        self.nextRedemptionLabelKey = nextRedemptionLabelKey
        self.sharesTickerLabelKey = sharesTickerLabelKey
        self.redemptionWindowNoteKey = redemptionWindowNoteKey
        self.redemptionPendingKey = redemptionPendingKey
        self.redemptionClaimableKey = redemptionClaimableKey
        self.claimAmountKey = claimAmountKey
        self.claimAvailableInDaysKey = claimAvailableInDaysKey
        self.usesComputedSettlementWindow = usesComputedSettlementWindow
        self.supportsCancel = supportsCancel
        self.cancelRequestKey = cancelRequestKey
    }
}

/// The seam every yield provider rides. Hides each provider's encoding model
/// (e.g. Circle's MSCA `execute()`-wrap, or a direct-EOA ERC-7540 vault) behind a
/// uniform payload builder surface; every builder returns a signable `KeysignPayload` whose coin
/// is the chain's native coin (calldata travels in `memo`), routed through the
/// shared Send verify/fee pipeline.
protocol DefiYieldProvider {
    var id: DefiYieldProviderID { get }
    var chain: Chain { get }
    /// USDC contract on `chain`.
    var assetContract: String { get }
    /// Circle provisions an MSCA via the Vultisig proxy; direct-EOA providers don't.
    var requiresAccountSetup: Bool { get }
    var depositsEnabled: Bool { get }
    /// Decimals of the deposited asset (USDC = 6). Used by the shared forms to
    /// convert human amounts to base units.
    var assetDecimals: Int { get }
    /// Contract a deposit targets, shown as the recipient on the display-only tx.
    var depositRecipient: String { get }
    /// Product minimum deposit in human (asset) units, e.g. `100` USDC.
    /// `0` means "no product minimum" (the form gates only on balance). Drives the
    /// deposit form's min-amount validator and info banner.
    var minDepositAmount: Decimal { get }
    /// Whether redemptions go through a settlement window or are instant
    /// (Circle). Drives the Withdraw-vs-Claim copy.
    var hasWindowedRedemption: Bool { get }
    /// Display copy + flags for the shared yield screens.
    var presentation: YieldPresentation { get }

    /// Whether the provider's account is ready (Circle MSCA created). Account-less
    /// providers are always provisioned. Gates the DeFi-list row visibility.
    @MainActor func isAccountProvisioned(vault: Vault) -> Bool

    // Account lifecycle — e.g. Circle SCA setup; a no-op for account-less providers.
    func resolveAccountAddress(vault: Vault) async throws -> String?
    func createAccount(vault: Vault) async throws -> String
    /// Persists a resolved account address onto the vault (Circle stores its MSCA
    /// address). Called on the main actor by the shell after `resolveAccountAddress`
    /// / `createAccount`; the default is a no-op for account-less providers.
    @MainActor func persistAccountAddress(_ address: String, vault: Vault)

    // Reads
    func refreshPosition(vault: Vault) async throws -> YieldVaultPosition
    func apy(vault: Vault) async throws -> Decimal?
    func tvl() async throws -> Decimal?

    // Write builders — all return a signable `KeysignPayload`.

    /// Deposit. When the provider gates deposits on an ERC-20 allowance and the
    /// current allowance is short, the returned payload bundles a prior `approve`
    /// (via `KeysignPayload.approvePayload`) so a first-time deposit signs
    /// approve→deposit in one keysign ceremony.
    func buildDepositPayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload
    /// Queued redemption request. For Circle (instant) this maps to `withdraw`.
    func buildRequestRedeemPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload
    /// Instant withdraw. Used when `maxWithdraw(user) >= amount` (liquidity now).
    func buildWithdrawPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload
    /// Collect a settled redemption from a windowed provider. Circle has no separate claim step.
    func buildClaimPayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload

    /// Cancel an in-flight redemption request (VULT's `cancelUnstake`), restoring
    /// the escrowed balance. Optional — the default throws "unsupported", so only
    /// providers whose `presentation.supportsCancel` is true need to implement it.
    func buildCancelUnstakePayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload

    /// Reads liquidity (`maxWithdraw`) to decide between an instant `withdraw`
    /// and a queued `requestRedeem`. Providers without instant liquidity return
    /// `false` and always queue.
    func canWithdrawInstantly(vault: Vault, amount: BigInt) async -> Bool
}

extension DefiYieldProvider {
    // Cancel is opt-in: providers without a cancel action (e.g. Circle) inherit
    // this default, which throws rather than silently building a no-op tx.
    // swiftlint:disable:next async_without_await
    func buildCancelUnstakePayload(vault _: Vault, recipient _: String, redemption _: YieldRedemption) async throws -> KeysignPayload {
        throw DefiYieldError.unsupportedOperation
    }

    /// Account-less providers (direct EOA) have nothing to persist.
    @MainActor func persistAccountAddress(_: String, vault _: Vault) {}

    /// Account-less providers are always provisioned; account-gated ones override.
    @MainActor func isAccountProvisioned(vault _: Vault) -> Bool { true }

    /// Most providers have no product minimum; the form gates only on balance.
    var minDepositAmount: Decimal { 0 }
}
