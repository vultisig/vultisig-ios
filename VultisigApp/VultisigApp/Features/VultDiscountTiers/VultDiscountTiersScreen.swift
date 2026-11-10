//
//  VultDiscountTiersScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI
import VultisigUIResources

struct VultDiscountTiersScreen: View {
    @ObservedObject var vault: Vault

    @State private var activeTier: VultDiscountTier?
    @State private var showTierSheet: VultDiscountTier?
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.openURL) var openURL

    private let service = VultTierService()
    /// Height over width of `vult-tiers-hero` (1179 × 1236 px).
    private let heroAspectRatio: CGFloat = 1236 / 1179
    /// Where the introduction starts, as a share of the hero's height (277pt of 412pt).
    private let introductionTopRatio: CGFloat = 277 / 412
    private let homeIndicatorBleed: CGFloat = 60
    #if os(macOS)
    private let horizontalPadding: CGFloat = 40
    private let bottomPadding: CGFloat = 24
    #else
    private let horizontalPadding: CGFloat = 16
    private let bottomPadding: CGFloat = 0
    #endif

    var body: some View {
        Screen {
            GeometryReader { geometry in
                let heroHeight = geometry.size.width * heroAspectRatio
                ZStack(alignment: .top) {
                    heroImage(height: heroHeight)
                        .frame(height: geometry.safeAreaInsets.top, alignment: .top)
                        .clipped()
                        .offset(y: -geometry.safeAreaInsets.top)

                    tierList(topInset: geometry.safeAreaInsets.top, heroHeight: heroHeight)
                }
            }
        }
        .screenTitle("vultDiscountTiers".localized)
        .screenEdgeInsets(.zero)
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
    /// Scrolls with the list. Only the strip behind the toolbar stays put, so
    /// the art can never sit under the introduction or the cards.
    func tierList(topInset: CGFloat, heroHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    introduction
                        .padding(.top, heroHeight * introductionTopRatio - topInset)
                        .padding(.bottom, 1)

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
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
                .background(alignment: .top) {
                    heroImage(height: heroHeight)
                        .offset(y: -topInset)
                }
            }
            // Clips the top edge only, so the cards still run under the home indicator.
            .mask { Rectangle().padding(.bottom, -homeIndicatorBleed) }
            .onLoad { scrollProxy = proxy }
        }
    }

    func heroImage(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .overlay(alignment: .top) {
                VultisigImage("vult-tiers-hero")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .allowsHitTesting(false)
    }

    var introduction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("vultDiscountTiersDescription".localized)
                .settingsText(.bodySRegular)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("vultDiscountTiersThorguardBoost".localized)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
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
