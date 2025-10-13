//
//  VultDiscountTiersScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import BigInt
import SwiftUI

struct VultDiscountTiersScreen: View {
    @ObservedObject var vault: Vault
    
    @State private var activeTier: VultDiscountTier?
    @State private var vultToken: Coin?
    @State private var showTierSheet: VultDiscountTier?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showSwapScren: Bool = false
    @Environment(\.openURL) var openURL
    
    private let service = VultTierService()
    
    var body: some View {
        Screen(showNavigationBar: false, edgeInsets: .init(bottom: 0)) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if let vultToken {
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
                                    isActive: activeTier == tier
                                ) {
                                    onExpand(tier: tier)
                                } onUnlock: {
                                    showTierSheet = tier
                                }
                                .id(tier.name)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
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
            VultDiscountTierBottomSheet(tier: tier) {
                showTierSheet = nil
                showSwapScren = true
            }
        }
        .onLoad {
            getVultToken()
            refreshVultBalance()
        }
        .refreshable {
            refreshVultBalance()
        }
        .navigationDestination(isPresented: $showSwapScren) {
            SwapCryptoView(
                fromCoin: vault.nativeCoin(for: .ethereum),
                toCoin: service.getVultToken(for: vault),
                vault: vault
            )
        }
    }
}

private extension VultDiscountTiersScreen {
    func onExpand(tier: VultDiscountTier) {
        withAnimation(.interpolatingSpring.delay(0.3)) {
            scrollProxy?.scrollTo(tier.name, anchor: .bottom)
        }
    }
    
    func refreshVultBalance() {
        Task {
            let activeTier = await service.fetchDiscountTier(for: vault)
            await MainActor.run {
                self.activeTier = activeTier
                getVultToken()
            }
        }
    }
    
    func getVultToken() {
        self.vultToken = service.getVultToken(for: vault)
    }
}

#Preview {
    VultDiscountTiersScreen(vault: .example)
}
