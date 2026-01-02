//
//  ActionButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-01.
//

import SwiftUI

struct ActionButton: View {
    let title: String
    let fontColor: Color
    
    var body: some View {
        Text(NSLocalizedString(title, comment: "").uppercased())
            .font(Theme.fonts.buttonSSemibold)
            .foregroundColor(fontColor)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(50)
            .overlay(
                RoundedRectangle(cornerRadius: 50)
                    .stroke(LinearGradient.primaryGradient, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    ActionButton(title: "send", fontColor: Theme.colors.bgButtonPrimary)
}
