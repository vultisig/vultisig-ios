//
//  NewWalletNameView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension NewWalletNameView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var main: some View {
        view
    }
    
    var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("nameYourVault", comment: ""))
                .font(.body34BrockmannMedium)
                .foregroundColor(.neutral0)
                .padding(.top, 16)
            
            Text(NSLocalizedString("newWalletNameDescription", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.extraLightGray)
            
            textfield
        }
        .padding(.horizontal, 16)
    }
}
#endif
