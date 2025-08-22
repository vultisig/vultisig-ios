//
//  VaultDetailQRCodeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension VaultDetailQRCodeView {
    var shareButton: some View {
        shareLinkButton
    }
    
    var buttons: some View {
        HStack(spacing: 22) {
            shareButton
            saveButton
        }
        .padding(.horizontal, 25)
    }
}
#endif
