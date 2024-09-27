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
    }
    
    var main: some View {
        view
    }
    
    var shareButton: some View {
        ZStack {
            if idiom == .phone {
                Button {
                    viewModel.shareImage(imageName)
                } label: {
                    FilledButton(title: "share")
                        .padding(.bottom, 22)
                }
            } else {
                shareLinkButton
            }
        }
    }
}
#endif
