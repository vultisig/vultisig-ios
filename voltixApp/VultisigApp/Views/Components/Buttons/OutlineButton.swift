//
//  OutlineButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct OutlineButton: View {
    let title: String
    
    @State var animateGradient = false
    
    var body: some View {
        Text(NSLocalizedString(title, comment: "Button Text"))
            .font(.body16MontserratBold)
            .foregroundStyle(LinearGradient.primaryGradient)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .cornerRadius(100)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(LinearGradient.primaryGradient, lineWidth: 1)
            )
    }
}

#Preview {
    OutlineButton(title: "importExistingVault")
}
