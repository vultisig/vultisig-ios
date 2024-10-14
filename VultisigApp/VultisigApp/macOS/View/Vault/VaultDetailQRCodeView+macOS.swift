//
//  VaultDetailQRCodeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension VaultDetailQRCodeView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "shareVaultQR")
    }

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
