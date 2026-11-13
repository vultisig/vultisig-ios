//
//  SwapReworkConfig.swift
//  VultisigApp
//
//  The reworked market swap (Swap R3) sits behind `isFeatureEnabled`, off by
//  default and switched on from Settings > Advanced (tap the version five
//  times), like the perps toggle. With it off every swap entry point builds
//  the existing `SwapDetailsScreen`, byte for byte.
//
//  The rework is presentation only: quotes, providers, fees, VULT tiers,
//  approvals, the review sheet with Paired / Fast Sign and the signing tail are
//  the existing swap services, read through `SwapDetailsViewModel`.
//

import Foundation

enum SwapReworkConfig {
    /// `@AppStorage` key of the Settings > Advanced toggle.
    static let featureFlagKey = "swapReworkEnabled"

    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: featureFlagKey)
    }

    /// Seconds a quote is shown before the form refreshes it. Mirrors the
    /// existing 59 s `SwapDetailsViewModel.timer`, so both forms re-quote on
    /// the same beat.
    static let quoteLifetime: TimeInterval = 60

    /// The existing `SwapDetailsViewModel.timer` counts down from this value
    /// to its re-quote; the countdown ring is a fraction of it.
    static let quoteRefreshTicks = 59

    /// Past this age without a successful refresh the quote is expired and
    /// review is blocked until a new one lands.
    static let quoteExpiryGrace: TimeInterval = 15

    /// A refresh that pays out less than the amount the user last saw by more
    /// than this share asks them to confirm the new amount before review.
    static let priceMoveThreshold: Decimal = Decimal(string: "0.0025") ?? 0

    /// How many tokens the picker remembers as recents.
    static let recentTokensLimit = 5

    #if DEBUG
    /// Debug-only fixture scenario (`-swapReworkDemo quote`): the screen renders
    /// fictional demo data instead of live quotes, so every state can be
    /// captured on a simulator without funds. Nothing in demo mode can reach
    /// the review sheet or signing.
    static var demoScenario: SwapReworkDemoScenario? {
        guard let raw = UserDefaults.standard.string(forKey: "swapReworkDemo") else { return nil }
        return SwapReworkDemoScenario(rawValue: raw)
    }
    #endif
}
