//
//  PercentageSliderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct PercentageSliderView: View {
    var onPercentage: (Int) -> Void
    
    @State private var percentage: Double = 100
    
    var body: some View {
        HStack(spacing: 12) {
            Text("0%")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
                
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
                
                Slider(value: $percentage, in: 0...100, step: 1)
                    .tint(Theme.colors.primaryAccent3)
                    .onChange(of: percentage) { oldValue, newValue in
                        onPercentage(Int(newValue))
                    }
            }
            
            Text("100%")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
        }
    }
}

#Preview {
    PercentageSliderView(onPercentage: { _ in })
}
