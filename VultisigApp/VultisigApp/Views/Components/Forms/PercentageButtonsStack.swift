//
//  PercentageButtonsStack.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct PercentageButtonsStack: View {
    let percentages: [Int] = [25, 50, 75, 100]
    var onPercentage: (Int) -> Void
    
    @State var selectedPercentage: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(percentages, id: \.self) { percentage in
                Button {
                    selectedPercentage = percentage
                    onPercentage(percentage)
                } label: {
                    buttonContent(for: percentage)
                }
            }
        }
    }
    
    @ViewBuilder
    private func buttonContent(for percentage: Int) -> some View {
        let isSelected = selectedPercentage == percentage
        let buttonText = percentage == 100 ? "MAX" : "\(percentage)%"
        
        Text(buttonText)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Capsule()
                        .fill(isSelected ? Theme.colors.primaryAccent3 : .clear)
                    Capsule()
                        .strokeBorder(Theme.colors.borderLight)
                }
            )
            .animation(.interpolatingSpring, value: isSelected)
    }
}

#Preview {
    PercentageButtonsStack { _ in }
}
