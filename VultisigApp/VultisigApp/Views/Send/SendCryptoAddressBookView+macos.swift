//
//  SendCryptoAddressBookView+macos.swift
//  VultisigApp
//
//  Created by Johnny Luo on 21/7/2025.
//

#if os(macOS)
import SwiftUI
extension SendCryptoAddressBookView {
    var content: some View {
        ZStack {
            Background()
                .frame(width: 500)
            
            VStack {
                headerMac
                listSelector
                list
            }
        }
    }
    var headerMac: some View {
        GeneralMacHeader(title: "addressBook")
    }

}

#endif
