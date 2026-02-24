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

    @State private var animationVM: RiveViewModel? = nil

    var body: some View {
        cell
            .onAppear {
                animationVM = RiveViewModel(fileName: "searching_device", autoPlay: true)
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

            if let index {
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
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.textSecondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var animation: some View {
        animationVM?.view()
            .frame(width: 32, height: 32)
    }

    private func badge(index: Int, totalCount: Int?) -> some View {
        Text("\(index) of \(totalCount.map { "\($0)" } ?? "\u{221E}")")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 99)
                    .stroke(Theme.colors.borderExtraLight, lineWidth: 1)
                    .fill(Theme.colors.bgSurface2)
            )
    }
}

#Preview {
    EmptyPeerCell(index: 3, totalCount: 3)
}
