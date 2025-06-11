//
//  OutlineButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct OutlineButton: View {
    let title: String
    
    var textColor = LinearGradient.primaryGradient
    var gradient = LinearGradient.primaryGradient
    
    @State var animateGradient = false
    
    var body: some View {
        container
    }
    
    var content: some View {
        Text(NSLocalizedString(title, comment: "Button Text"))
            .foregroundStyle(textColor)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .cornerRadius(100)
            .overlay(
                overlay
            )
    }
}

#Preview {
    OutlineButton(title: "importExistingVault")
}
