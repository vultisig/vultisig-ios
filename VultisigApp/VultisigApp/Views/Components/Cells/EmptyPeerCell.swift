//
//  EmptyPeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-29.
//

import SwiftUI
import RiveRuntime

struct EmptyPeerCell: View {
    var index: Int? = nil
    var totalCount: Int? = nil

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
        HStack(spacing: 12) {
            animation
            text
            Spacer()

            if let index, let totalCount {
                badge(index: index, totalCount: totalCount)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 68)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .padding(1)
    }

    var text: some View {
        Text(NSLocalizedString("waitingForDeviceToJoin", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var animation: some View {
        animationVM?.view()
            .frame(width: 24, height: 24)
    }

    private func badge(index: Int, totalCount: Int) -> some View {
        Text("\(index) of \(totalCount)")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }
}

#Preview {
    EmptyPeerCell(index: 3, totalCount: 3)
}
