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
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: CircleConstants.Design.verticalSpacing) {
                        topBanner
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                                .font(.headline)
                                .foregroundStyle(Theme.colors.textPrimary)
                            
                            Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                                .font(.body)
                                .foregroundStyle(Theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        InfoBannerView(
                            description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: nil,
                            onClose: {
                                withAnimation { appClosedBanners.append(circleDashboardBannerId) }
                            }
                        )
                        .showIf(showInfoBanner)
                        
                        if let error = model.error {
                            InfoBannerView(
                                description: error.localizedDescription,
                                type: .error,
                                leadingIcon: nil,
                                onClose: {
                                    withAnimation { model.error = nil }
                                }
                            )
                        }
                        
                        usdcDepositedCard
                    }
                    .padding(.top, CircleConstants.Design.mainViewTopPadding)
                    .padding(.bottom, CircleConstants.Design.mainViewBottomPadding)
                    .padding(.horizontal, CircleConstants.Design.horizontalPadding)
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .onAppear {
            Task { await loadData() }
        }
    }
}
#endif
