//
//  VaultDetailScanButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension VaultDetailScanButton {
    var content: some View {
        ZStack {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                macContent
            } else {
                phoneContent
            }
        }
    }
    
    var phoneContent: some View {
        Button {
            showSheet.toggle()
        } label: {
            label
        }
    }
    
    var macContent: some View {
        NavigationLink {
            GeneralQRImportMacView(type: .SignTransaction)
        } label: {
            label
        }
    }
}
#endif
