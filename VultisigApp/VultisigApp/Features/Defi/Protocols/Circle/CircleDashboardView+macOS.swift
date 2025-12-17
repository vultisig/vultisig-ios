//
//  CircleDashboardView+macOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

#if os(macOS)
extension CircleDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    topBanner
                    
                    headerDescription
                    
                    if showInfoBanner {
                        infoBanner
                    }
                    
                    usdcDepositedCard
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            Task { await loadData() }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                NavigationBackButton()
            }
        }
    }
    
    var headerDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                .font(.headline)
                .foregroundStyle(Theme.colors.textPrimary)
            
            Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                .font(.body)
                .foregroundStyle(Theme.colors.textLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
    
    var infoBanner: some View {
        InfoBannerView(
            description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
            type: .info,
            leadingIcon: "info.circle",
            onClose: {
                withAnimation { showInfoBanner = false }
            }
        )
        .padding(.horizontal, 16)
    }
}
#endif
