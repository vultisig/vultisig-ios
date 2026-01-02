//
//  SwapRefreshQuoteCounter.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapRefreshQuoteCounter: View {
    let timer: Int
    
    var body: some View {
        HStack(spacing: 8) {
            label
            loader
        }
        .animation(.easeInOut, value: timer)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(24)
    }
    
    var label: some View {
        Group {
            Text("0:") +
            Text(String(format: "%02d", timer))
        }
        .font(Theme.fonts.caption12)
        .foregroundColor(Theme.colors.textPrimary)
    }
    
    var loader: some View {
        ZStack {
            Circle()
                .stroke(
                    Theme.colors.border,
                    lineWidth: 2
                )
            
            Circle()
                .trim(from: 0, to: Double(timer)/60)
                .stroke(
                    Theme.colors.primaryAccent4,
                    lineWidth: 2
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }
}

#Preview {
    SwapRefreshQuoteCounter(timer: 59)
}
