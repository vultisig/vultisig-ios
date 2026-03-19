//
//  PercentageButtonsStack.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct PercentageButtonsStack: View {
    let percentages: [Double]
    @Binding var selectedPercentage: Double?

    init(percentages: [Double] = [25, 50, 75, 100], selectedPercentage: Binding<Double?>) {
        self.percentages = percentages
        self._selectedPercentage = selectedPercentage
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(percentages, id: \.self) { percentage in
                Button {
                    selectedPercentage = percentage
                } label: {
                    buttonContent(for: percentage)
                }
            }
        }
    }

    @ViewBuilder
    private func buttonContent(for percentage: Double) -> some View {
        let isSelected = selectedPercentage == percentage
        let buttonText = percentage == 100 ? "MAX" : (Double(percentage) / 100).formatted(.percent)

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
    @Previewable @State var percentage: Double? = nil
    PercentageButtonsStack(selectedPercentage: $percentage)
}
