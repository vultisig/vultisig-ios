//
//  OutlineButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct OutlineButton: View {
    let title: String
    var gradient = LinearGradient.primaryGradient
    
    @State var animateGradient = false
    
    var body: some View {
        container
    }
    
    var content: some View {
        Text(NSLocalizedString(title, comment: "Button Text"))
            .foregroundStyle(gradient)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .cornerRadius(100)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                #if os(iOS)
                    .stroke(gradient, lineWidth: 1)
                #elseif os(macOS)
                    .stroke(gradient, lineWidth: 2)
                #endif
            )
    }
}

#Preview {
    OutlineButton(title: "importExistingVault")
}
