//
//  ChainHeaderCell+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension ChainHeaderCell {
    var showQRButton: some View {
        NavigationLink {
            AddressQRCodeView(
                addressData: group.address,
                vault: vault,
                groupedChain: group,
                showSheet: $showQRcode,
                isLoading: $isLoading
            )
        } label: {
            qrCodeLabel
        }
    }
    
    func copyAddress() {
        showAlert = true
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(group.address, forType: .string)
    }
}
#endif
