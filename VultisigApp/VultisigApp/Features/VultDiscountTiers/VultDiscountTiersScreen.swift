//
//  VultDiscountTiersScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import BigInt
import SwiftUI

struct VultDiscountTiersScreen: View {
    @Environment(\.router) var router
    @ObservedObject var vault: Vault

    @State private var activeTier: VultDiscountTier?
    @State private var vultToken: Coin?
    @State private var showTierSheet: VultDiscountTier?
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.openURL) var openURL
    
    private let service = VultTierService()
    
    var body: some View {
        Screen(showNavigationBar: false, edgeInsets: .init(bottom: 0)) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        Image("vult-banner")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 500)
                            .padding(.bottom, 10)
                        
                        Text("vultDiscountTiersDescription".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        
                        ForEach(VultDiscountTier.allCases) { tier in
                            VultDiscountTierView(
                                tier: tier,
                                vultToken: vultToken,
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
        .crossPlatformToolbar("vultDiscountTiers".localized) {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "globus") {
                    openURL(StaticURL.VultisigVultURL)
                }
            }
        }
        .crossPlatformSheet(item: $showTierSheet) { tier in
            VultDiscountTierBottomSheet(
                tier: tier,
                isPresented: Binding(get: { showTierSheet != nil }, set: { _ in showTierSheet = nil })
            ) {
                showTierSheet = nil
                router.navigate(to: VaultRoute.swap(
                    fromCoin: vault.nativeCoin(for: .ethereum),
                    toCoin: service.getVultToken(for: vault),
                    vault: vault
                ))
            }
        }
        .onLoad {
            getVultToken()
            getVultTier()
            fetchVultTier()
        }
        .refreshable {
            fetchVultTier()
        }
    }
}

private extension VultDiscountTiersScreen {
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
                getVultToken()
            }
        }
    }
    
    func getVultToken() {
        self.vultToken = service.getVultToken(for: vault)
    }
    
    func canUnlock(tier: VultDiscountTier) -> Bool {
        let tiers = VultDiscountTier.allCases.sorted { $0.balanceToUnlock < $1.balanceToUnlock }
        guard let currentIndex = tiers.firstIndex(where: { $0 == activeTier }) else {
            return true
        }
        
        let tierIndex = tiers.firstIndex(where: { $0 == tier }) ?? 0
        return tierIndex > currentIndex
    }
}

#Preview {
    VultDiscountTiersScreen(vault: .example)
}
