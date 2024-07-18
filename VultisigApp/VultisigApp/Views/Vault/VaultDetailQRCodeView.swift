//
//  VaultDetailQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailQRCodeView: View {
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("shareVaultQR", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var content: some View {
        VStack {
            Spacer()
            qrCode
            Spacer()
            button
        }
        .padding(15)
    }
    
    var qrCode: some View {
        VStack {
            
        }
    }
    
    var button: some View {
        FilledButton(title: "saveOrShare")
            .padding(.bottom, 10)
    }
}

#Preview {
    VaultDetailQRCodeView()
}
