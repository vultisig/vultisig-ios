//
//  SetupVaultSecureText.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-27.
//

import SwiftUI

struct SetupVaultSecureText: View {
    let selectedTab: SetupVaultState
    
    var body: some View {
        VStack(spacing: 0) {
            header
            dashedLine
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .cornerRadius(16)
        .padding(.vertical, 16)
    }
    
    var header: some View {
        ZStack {
            if selectedTab == .fast {
                headerText
                    .foregroundStyle(LinearGradient.primaryGradient)
            } else {
                headerText
                    .foregroundColor(.alertTurquoise)
            }
        }
    }
    
    var headerText: some View {
        Text(selectedTab.secureTextTitle)
            .font(.body18BrockmannMedium)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }
    
    var dashedLine: some View {
        Rectangle()
           .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
           .frame(height: 2)
           .frame(maxWidth: .infinity)
           .foregroundColor(Color.blue400)
           .offset(y: 1)
    }
    
    var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3) { index in
                    Image(systemName: "checkmark")
                        .foregroundColor(Color.turquoise400)
                        .frame(width: 16, height: 16)
                }
            }
            
            Text(selectedTab.secureTextDecription)
                .foregroundColor(.neutral0)
                .lineSpacing(12)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .font(.body14BrockmannMedium)
        .padding(24)
        .background(Color.blue600)
    }
}

#Preview {
    SetupVaultSecureText(selectedTab: .secure)
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}
