//
//  PerpsConfig.swift
//  VultisigApp
//
//  Hyperliquid perps configuration. The whole feature sits behind
//  `isFeatureEnabled`, off by default and switched on from Settings >
//  Advanced (tap the version five times), like the other in-progress
//  toggles there. Every perps surface (DeFi row, routes, review) checks it.
//

import Foundation

enum PerpsConfig {
    /// `@AppStorage` key of the Settings > Advanced toggle.
    static let featureFlagKey = "perpsEnabled"

    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: featureFlagKey)
    }

    /// Debug-only details (digests, request kinds, the dry-run log, account
    /// mode). Off unless launched with `-perpsDebugDetails YES`.
    static var showsDebugDetails: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "perpsDebugDetails")
        #else
        false
        #endif
    }

    /// Debug-only: view another address's public Hyperliquid account to
    /// exercise the positions/orders UI (`-perpsDebugAddressOverride 0x…`
    /// launch argument). Read-only, and the hub labels it while active.
    static var debugAddressOverride: String? {
        #if DEBUG
        guard let value = UserDefaults.standard.string(forKey: "perpsDebugAddressOverride"),
              (try? HLAddress.bytes(value)) != nil else { return nil }
        return value
        #else
        nil
        #endif
    }

    #if DEBUG
    /// Hides the beta tag for demo recordings (`-perpsDemoRecording YES`).
    static var isRecordingDemo: Bool { UserDefaults.standard.bool(forKey: "perpsDemoRecording") }

    /// A fictional funded account for demos (`-perpsDemoAccount YES`).
    static var usesDemoAccount: Bool { UserDefaults.standard.bool(forKey: "perpsDemoAccount") }

    /// A long vault name (`-perpsDemoVaultName "…"`), to check the "To" row
    /// truncates on the withdraw screen and its review.
    static var debugVaultName: String? { UserDefaults.standard.string(forKey: "perpsDemoVaultName") }
    #endif

    /// The Hyperliquid account perps reads: the vault's trading account
    /// (m/44'/60'/0'/0/1000), or the debug override.
    @MainActor
    static func tradingAccountAddress(vault: Vault) -> String? {
        debugAddressOverride ?? PerpsDerivedAccount.derive(.trading, vault: vault)?.address
    }

    /// Mainnet. Only the read-only info API is called; nothing is submitted to `/exchange` yet.
    static let isMainnet = true

    /// No signing CTA proceeds to the shared `SigningRoute` while this is false,
    /// and nothing flips it at runtime. Live signing (submission to `/exchange`,
    /// the derive path carried to co-signers) lands in a follow-up.
    static let allowsSigning = false

    /// User-signed domain chain id. Any chain is valid; the spec recommends
    /// Arbitrum One. The SDK parity tests use the SDK's 0x66eee.
    static let signatureChainId: UInt64 = 0xa4b1

    /// Ticket leverage presets, and the cap on the first trade. Presets above
    /// the cap render disabled.
    static let leveragePresets = [1, 2, 3, 5, 10]
    static let firstTradeMaxLeverage = 3
    static let defaultLeverage = 2
    /// Default stop distance from entry, clamped to stay inside liquidation.
    static let defaultStopDistance: Decimal = Decimal(string: "0.07") ?? 0

    /// The Vultisig EVM fee address, read from the swap integration rather than
    /// retyped, so it can never drift to a look-alike (address poisoning). Needs
    /// >= 100 USDC perps account value on Hyperliquid to collect builder fees.
    /// Lowercased on the wire.
    static let builderAddress = KyberSwapService.referrerAddress
    /// Builder fee before any VULT discount: 100 tenths of a bp = 10 bps = 0.1% (Alexandre, 2026-11-13).
    static let builderFeeTenthsBp = 100
    /// Approval cap: the undiscounted fee, the same for every tier, so a tier
    /// change never needs a new approval.
    static let builderMaxFeeRate = "0.1%"

    /// The builder fee after the vault's VULT tier, scaled from the swap table:
    /// a tier's swap discount over the 50 bps swap list fee, applied to this base.
    /// Bronze 90, Silver 80, Gold 60, Platinum 50, Diamond 30, Ultimate 0 (tenths of a bp).
    static func builderFeeTenthsBp(tier: VultDiscountTier?) -> Int {
        guard let tier else { return builderFeeTenthsBp }
        let list = SwapCryptoLogic.affiliateListFeeBps
        return builderFeeTenthsBp * (list - max(0, min(tier.bpsDiscount, list))) / list
    }

    /// Nil when the tier waives the fee: the order then carries no builder field.
    static func builderFee(tier: VultDiscountTier?) -> HLBuilderFee? {
        let tenths = builderFeeTenthsBp(tier: tier)
        return tenths > 0 ? HLBuilderFee(builder: builderAddress, tenthsOfBasisPoint: tenths) : nil
    }

    static func builderFeeRate(tier: VultDiscountTier?) -> Decimal { Decimal(builderFeeTenthsBp(tier: tier)) / 100_000 }
    /// The undiscounted rate, the "Vultisig 0.1%" line before any VULT discount.
    static var listBuilderFeeRate: Decimal { builderFeeRate(tier: nil) }
    /// For the vault's current tier (`PerpsVultTier`).
    static var builderFee: HLBuilderFee? { builderFee(tier: PerpsVultTier.current) }
    static var builderFeeRate: Decimal { builderFeeRate(tier: PerpsVultTier.current) }

    /// Agent approval: name plus an on-chain `valid_until` (max 180 days).
    static let agentName = "vultisig"
    static let agentLifetimeMs: UInt64 = 7 * 86_400_000

    /// Deposits go CCTP from Arbitrum into the trading account (`HLCctp`), never
    /// Bridge2, which credits the sender's (main) address.
    /// withdraw3 to Arbitrum: $1 fee, about 5 minutes.
    static let withdrawFee: Decimal = 1
}

/// The vault's VULT discount tier, resolved with the swap path's own
/// `VultTierService.resolveTierForSession` (VULT balance + Thorguard bump) and
/// kept for the builder fee. Debug only: `-perpsDemoVultTier gold` pins one.
enum PerpsVultTier {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var resolved: VultDiscountTier?

    static var current: VultDiscountTier? {
        if let demo = demoTier { return demo }
        return lock.withLock { resolved }
    }

    @MainActor
    static func refresh(vault: Vault, resolver: SwapDiscountTierResolving = VultTierService()) async {
        let tier = await resolver.resolveTierForSession(for: vault)
        lock.withLock { resolved = tier }
    }

    private static var demoTier: VultDiscountTier? {
        #if DEBUG
        guard PerpsConfig.usesDemoAccount, let raw = UserDefaults.standard.string(forKey: "perpsDemoVultTier") else { return nil }
        return VultDiscountTier(rawValue: raw.lowercased())
        #else
        nil
        #endif
    }
}
