//
//  VaultDetailScanButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI

struct VaultDetailScanButton: View {
    @Binding var showSheet: Bool

    let vault: Vault
    let sendTx: SendTransaction
    
    var body: some View {
        content
    }
    
    var label: some View {
        ZStack {
            Circle()
                .foregroundColor(.blue800)
                .frame(width: 80, height: 80)
                .opacity(0.8)
            
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
}

#Preview {
    VaultDetailScanButton(showSheet: .constant(true), vault: .example, sendTx: SendTransaction())
}
