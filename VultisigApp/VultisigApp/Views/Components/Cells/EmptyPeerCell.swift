//
//  EmptyPeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-29.
//

import SwiftUI
import RiveRuntime

struct EmptyPeerCell: View {
    @State var animationVM: RiveViewModel? = nil

    var body: some View {
        cell
            .onAppear {
                animationVM = RiveViewModel(fileName: "WaitingForDevice", autoPlay: true)
            }
            .onDisappear {
                animationVM?.stop()
            }
    }

    var cell: some View {
        HStack(spacing: 8) {
            animation
            text
            Spacer()
        }
        .padding(16)
        .frame(height: 70)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .padding(1)
    }

    var text: some View {
        Text(NSLocalizedString("waitingOnDevice", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var animation: some View {
        animationVM?.view()
            .frame(width: 24, height: 24)
    }

}

#Preview {
    EmptyPeerCell()
}
