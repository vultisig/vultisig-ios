//
//  EditAddressBookView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension EditAddressBookView {
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
        GeneralMacHeader(title: "editAddress")
    }
    
    var view: some View {
        VStack(spacing: 22) {
            fields
            button
        }
        .padding(.horizontal, 16)
        .padding(.horizontal, 24)
        .alert(isPresented: $showAlert) {
            alert
        }
    }
}
#endif
