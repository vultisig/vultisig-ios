//
//  VultDiscountTiersScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI

struct VultDiscountTiersScreen: View {
    @ObservedObject var vault: Vault

    @State private var activeTier: VultDiscountTier?
    @State private var showTierSheet: VultDiscountTier?
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.openURL) var openURL

    private let service = VultTierService()

    var body: some View {
        Screen {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        heroBanner
                            .padding(.bottom, 4)

                        Text("vultDiscountTiersDescription".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        ForEach(VultDiscountTier.allCases) { tier in
                            VultDiscountTierView(
                                tier: tier,
                                isActive: activeTier == tier,
                                canUnlock: canUnlock(tier: tier)
                            ) {
                                onExpand(tier: tier)
                            } onUnlock: {
                                showTierSheet = tier
                            }
                            .id(tier.name)
                        }
                    }
                }
                #if os(macOS)
                .padding(.bottom, 24)
                #endif
                .onLoad { scrollProxy = proxy }
            }
        }
        .screenTitle("vultDiscountTiers".localized)
        .screenEdgeInsets(.init(bottom: 0))
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: .globe2) {
                    openURL(StaticURL.VultisigVultURL)
                }
            }
        }
        .tierGated(presentedTier: $showTierSheet, vault: vault)
        .onLoad {
            getVultTier()
            fetchVultTier()
        }
        .refreshable {
            fetchVultTier()
        }
    }
}

private extension VultDiscountTiersScreen {
    var heroBanner: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Theme.colors.bgSurface1, Theme.colors.primaryAccent1],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .overlay(
                Image("vult-tiers-hero-coins")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 169)
                    .offset(x: 8, y: -8),
                alignment: .topTrailing
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("vultDiscountHeroTitle".localized)
                    .font(Theme.fonts.title1)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("vultDiscountHeroSubtitle".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 139)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    func onExpand(tier: VultDiscountTier) {
        withAnimation(.interpolatingSpring.delay(0.3)) {
            scrollProxy?.scrollTo(tier.name, anchor: .bottom)
        }
    }

    func getVultTier() {
        fetchDiscountTier(cached: true)
    }

    func fetchVultTier() {
        fetchDiscountTier(cached: false)
    }

    func fetchDiscountTier(cached: Bool) {
        Task {
            let activeTier = await service.fetchDiscountTier(for: vault, cached: cached)
            await MainActor.run {
                self.activeTier = activeTier
            }
        }
    }

    func canUnlock(tier: VultDiscountTier) -> Bool {
        VultDiscountTier.canUnlock(tier, active: activeTier)
    }
}

#Preview {
    VultDiscountTiersScreen(vault: .example)
}
