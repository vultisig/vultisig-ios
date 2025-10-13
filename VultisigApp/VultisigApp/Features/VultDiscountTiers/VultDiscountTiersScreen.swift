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
    @State private var showTierSheet: VultDiscountTier?
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Screen(showNavigationBar: false, edgeInsets: .init(bottom: 0)) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        Image("vult-banner")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.bottom, 10)
                        
                        Text("vultDiscountTiersDescription".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        
                        ForEach(VultDiscountTier.allCases) { tier in
                            VultDiscountTierView(tier: tier, isActive: activeTier == tier) {
                                onExpand(tier: tier)
                            } onUnlock: {
                                showTierSheet = tier
                            }
                            .id(tier.name)
                        }
                    }
                }
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
                onUnlock(tier: tier)
            }
        }
        .onLoad {
            refreshVultBalance()
        }
        .refreshable {
            refreshVultBalance()
        }
    }
}

private extension VultDiscountTiersScreen {
    func onUnlock(tier: VultDiscountTier) {
        // TODO: - Redirect to swaps
    }
    
    func onExpand(tier: VultDiscountTier) {
        withAnimation(.interpolatingSpring.delay(0.3)) {
            scrollProxy?.scrollTo(tier.name, anchor: .bottom)
        }
    }
    
    func refreshVultBalance() {
        Task {
            let activeTier = await VultTierService().fetchDiscountTier(for: vault)
            await MainActor.run { self.activeTier = activeTier }
        }
        
    }
}

#Preview {
    VultDiscountTiersScreen(vault: .example)
}
