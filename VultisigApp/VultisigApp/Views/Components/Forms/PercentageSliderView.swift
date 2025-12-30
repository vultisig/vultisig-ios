//
//  PercentageSliderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct PercentageSliderView: View {
    @Binding var percentage: Double?
    let minimumValue: Double
    
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { percentage ?? 100 },
            set: { percentage = $0 }
        )
    }
    
    init(percentage: Binding<Double?>, minimumValue: Double = 0) {
        self._percentage = percentage
        self.minimumValue = minimumValue
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text((minimumValue / 100).formatted(.percent))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(Theme.colors.border)
                            .frame(width: 4, height: 4)
                        if index < 4 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .offset(y: 12)
                
                Slider(value: sliderBinding, in: minimumValue...100, step: 1)
                    .tint(Theme.colors.primaryAccent3)
            }
            
            Text(100.formatted(.percent))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}

#Preview {
    @Previewable @State var percentage: Double? = nil
    PercentageSliderView(percentage: $percentage)
}
