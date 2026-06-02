//
//  TierGatedTap.swift
//  VultisigApp
//
//  Shared VULT-tier gate-on-tap helper. A single source of truth for the
//  "tap a tier-locked entry → either run the action (unlocked) or present the
//  upsell bottom sheet that redirects to the buy-VULT swap (locked)" pattern.
//  Used by both the Custom RPC General-settings entry and
//  `VultDiscountTiersScreen`.
//

import SwiftUI

/// Decision logic for a tier-gated tap. Resolves the vault's tier via
/// `TierGate`; when the vault meets `required` it runs `onUnlocked`, otherwise
/// it surfaces the upsell sheet for the tier to present.
enum TierGatedTap {
    /// Resolves the gate for `required` and either runs `onUnlocked` (vault is
    /// entitled) or assigns the tier to surface the upsell sheet (locked).
    /// - Parameters:
    ///   - required: minimum tier the entry requires.
    ///   - show: the tier presented for the upsell — set to `required` when locked.
    ///   - vault: the vault whose tier is resolved.
    ///   - isUnlocked: resolves whether `vault` meets `required`. Defaults to
    ///     the production `TierGate`; injectable for testing the decision logic.
    ///   - onUnlocked: action run when the vault is entitled.
    @MainActor
    static func handle(
        required: VultDiscountTier,
        show: Binding<VultDiscountTier?>,
        for vault: Vault,
        isUnlocked: (VultDiscountTier, Vault) async -> Bool = { tier, vault in
            await TierGate().isUnlocked(tier, for: vault)
        },
        onUnlocked: @escaping () -> Void
    ) async {
        if await isUnlocked(required, vault) {
            onUnlocked()
        } else {
            show.wrappedValue = required
        }
    }
}

private struct TierGatedModifier: ViewModifier {
    @Environment(\.router) var router
    @Binding var presentedTier: VultDiscountTier?
    let vault: Vault
    private let service = VultTierService()

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(item: $presentedTier) { tier in
                VultDiscountTierBottomSheet(
                    tier: tier,
                    isPresented: Binding(
                        get: { presentedTier != nil },
                        set: { _ in presentedTier = nil }
                    )
                ) {
                    presentedTier = nil
                    router.navigate(to: VaultRoute.swap(
                        fromCoin: vault.nativeCoin(for: .ethereum),
                        toCoin: service.getVultToken(for: vault),
                        vault: vault
                    ))
                }
            }
    }
}

extension View {
    /// Presents the VULT-tier upsell bottom sheet for `presentedTier` and, on
    /// unlock, redirects to the buy-VULT swap. Pair with
    /// `TierGatedTap.handle(...)` which sets `presentedTier` when locked.
    func tierGated(presentedTier: Binding<VultDiscountTier?>, vault: Vault) -> some View {
        modifier(TierGatedModifier(presentedTier: presentedTier, vault: vault))
    }
}
