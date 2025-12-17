//
//  CircleDashboardView+iOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

#if os(iOS)
extension CircleDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    topBanner
                    
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
                    
                    if showInfoBanner {
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
                    
                    usdcDepositedCard
                }
                .padding(.vertical, 20)
            }
            .refreshable {
                await loadData()
            }
        }
        .onAppear {
            Task { await loadData() }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
}
#endif
