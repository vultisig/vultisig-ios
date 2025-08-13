//
//  SendCryptoView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString(sendCryptoViewModel.currentTitle, comment: "SendCryptoView title"))
            .toolbar {
                if sendCryptoViewModel.currentIndex == 3 {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationQRShareButton(
                            vault: vault,
                            type: .Keysign,
                            viewModel: shareSheetViewModel
                        )
                    }
                }
            }
            .toolbarBackground(Theme.colors.bgPrimary)
    }
    
    var main: some View {
        view
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear(){
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
#endif
