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
            .foregroundStyle(LinearGradient.primaryGradient)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .cornerRadius(100)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                #if os(iOS)
                    .stroke(LinearGradient.primaryGradient, lineWidth: 1)
                #elseif os(macOS)
                    .stroke(LinearGradient.primaryGradient, lineWidth: 2)
                #endif
            )
#if os(iOS)
            .font(.body16MontserratBold)
#elseif os(macOS)
            .font(.body14MontserratBold)
#endif
    }
}

#Preview {
    OutlineButton(title: "importExistingVault")
}
