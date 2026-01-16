//
//  TronDashboardView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: TronConstants.Design.verticalSpacing) {
                        topBanner
                        
                        resourcesCard
                        
                        actionsCard
                        
                        if let error = model.error, error.localizedDescription.lowercased() != "cancelled" {
                            InfoBannerView(
                                description: error.localizedDescription,
                                type: .error,
                                leadingIcon: nil,
                                onClose: {
                                    withAnimation { model.error = nil }
                                }
                            )
                        }
                        
                        pendingWithdrawalsCard
                    }
                    .padding(.top, TronConstants.Design.mainViewTopPadding)
                    .padding(.bottom, TronConstants.Design.mainViewBottomPadding)
                    .padding(.horizontal, TronConstants.Design.horizontalPadding)
                }
                .refreshable {
                    await onRefresh()
                }
            }
        }
    }
}
#endif
