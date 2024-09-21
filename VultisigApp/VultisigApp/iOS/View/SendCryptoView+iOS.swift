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
                if sendCryptoViewModel.currentIndex != 1 {
                    ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                        backButton
                    }
                }
                if showFeeSettings {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        settingsButton
                    }
                }
                if sendCryptoViewModel.currentIndex == 3 {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationQRShareButton(
                            vault: vault,
                            type: .Keysign,
                            renderedImage: shareSheetViewModel.renderedImage
                        )
                    }
                }
            }
    }
    
    var main: some View {
        view
    }
}
#endif
