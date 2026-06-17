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
    case noon
}

/// Read model for a single redemption. Circle redemptions are always instant
/// (no queue → `claimableAt == nil`); Noon redemptions are windowed.
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
/// generic shells render each vault's labels (Circle vs Noon) without branching
/// on the id. Strings are localization keys, resolved at the view via `.localized`.
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

    /// Provider name shown small/secondary at the top of the banner ("Noon" / "Circle").
    let providerNameKey: String
    /// Asset name for the badge logo shown (clipped to a circle) in the top banner.
    let bannerLogoAsset: String
    /// Closable info banner body shown on the empty/setup state.
    let infoBannerKey: String
}

/// The seam both Circle and Noon ride. Hides the two encoding models (Circle
/// MSCA `execute()`-wrap vs Noon direct-EOA ERC-7540) behind a uniform payload
/// builder surface; every builder returns a signable `KeysignPayload` whose coin
/// is the chain's native coin (calldata travels in `memo`), routed through the
/// shared Send verify/fee pipeline.
protocol DefiYieldProvider {
    var id: DefiYieldProviderID { get }
    var chain: Chain { get }
    /// USDC contract on `chain`.
    var assetContract: String { get }
    /// Circle provisions an MSCA via the Vultisig proxy; Noon is a direct EOA.
    var requiresAccountSetup: Bool { get }
    var depositsEnabled: Bool { get }
    /// Decimals of the deposited asset (USDC = 6). Used by the shared forms to
    /// convert human amounts to base units.
    var assetDecimals: Int { get }
    /// Contract a deposit targets, shown as the recipient on the display-only tx.
    var depositRecipient: String { get }
    /// Product minimum deposit in human (asset) units, e.g. `100` USDC for Noon.
    /// `0` means "no product minimum" (the form gates only on balance). Drives the
    /// deposit form's min-amount validator and info banner.
    var minDepositAmount: Decimal { get }
    /// Whether redemptions go through a settlement window (Noon) or are instant
    /// (Circle). Drives the Withdraw-vs-Claim copy.
    var hasWindowedRedemption: Bool { get }
    /// Display copy + flags for the shared yield screens.
    var presentation: YieldPresentation { get }

    // Account lifecycle — Circle SCA setup; Noon is a no-op.
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
    /// Instant withdraw. For Noon, used when `maxWithdraw(user) >= amount`.
    func buildWithdrawPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload
    /// Collect a settled redemption (Noon). Circle has no separate claim step.
    func buildClaimPayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload

    /// Reads liquidity (`maxWithdraw`) to decide between an instant `withdraw`
    /// and a queued `requestRedeem`. Providers without instant liquidity return
    /// `false` and always queue.
    func canWithdrawInstantly(vault: Vault, amount: BigInt) async -> Bool
}

extension DefiYieldProvider {
    /// Account-less providers (Noon, direct EOA) have nothing to persist.
    @MainActor func persistAccountAddress(_: String, vault _: Vault) {}

    /// Most providers have no product minimum; the form gates only on balance.
    var minDepositAmount: Decimal { 0 }
}
