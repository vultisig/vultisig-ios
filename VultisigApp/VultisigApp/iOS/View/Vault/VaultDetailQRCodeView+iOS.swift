//
//  VaultDetailQRCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension VaultDetailQRCodeView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("shareVaultQR", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
    }
    
    var buttons: some View {
        VStack(spacing: 22) {
            shareButton
            saveButton
        }
    }
    
    var shareButton: some View {
        ZStack {
            if idiom == .phone {
                PrimaryButton(
                    title: "share",
                    leadingIcon: "square.and.arrow.up"
                ) {
                    viewModel.shareImage(imageName)
                }
            } else {
                shareLinkButton
            }
        }
    }
}
#endif
