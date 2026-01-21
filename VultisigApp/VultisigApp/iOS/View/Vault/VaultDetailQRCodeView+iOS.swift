//
//  VaultDetailQRCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension VaultDetailQRCodeView {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var buttons: some View {
        VStack(spacing: 16) {
            shareButton
            saveButton
        }
    }
    
    var shareButton: some View {
        ZStack {
            if idiom == .phone {
                PrimaryButton(title: "share") {
                    viewModel.shareImage(imageName)
                }
            } else {
                shareLinkButton
            }
        }
    }
}
#endif
