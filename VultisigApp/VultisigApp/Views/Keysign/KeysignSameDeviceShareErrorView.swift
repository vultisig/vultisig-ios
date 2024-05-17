//
//  KeysignSameDeviceShareErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-16.
//

import SwiftUI

struct KeysignSameDeviceShareErrorView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            errorMessage
            Spacer()
            tryAgainButton
        }
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "sameDeviceShareError")
    }
    
    var tryAgainButton: some View {
        NavigationLink {
            HomeView(showVaultsList: true)
        } label: {
            FilledButton(title: "goToHomeView")
        }
        .padding(40)
    }
}

#Preview {
    ZStack {
        Background()
        KeysignSameDeviceShareErrorView()
    }
}
