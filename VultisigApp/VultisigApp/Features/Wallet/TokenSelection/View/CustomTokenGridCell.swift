//
//  CustomTokenGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct CustomTokenGridCell: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                VStack {
                    Icon(named: "plus-large", size: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.colors.bgSurface1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .inset(by: 0.75)
                        .strokeBorder(Theme.colors.border, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                )

                Text("custom".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 74, height: 100)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CustomTokenGridCell {}
}
