//
//  ThisDevicePeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-17.
//

import SwiftUI

struct ThisDevicePeerCell: View {
    let deviceName: String
    var index: Int? = nil
    var totalCount: Int? = nil

    var body: some View {
        cell
    }

    var cell: some View {
        HStack(spacing: 12) {
            deviceIcon

            VStack(alignment: .leading, spacing: 2) {
                deviceId
                description
            }

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

    var deviceIcon: some View {
        Circle()
            .fill(Theme.colors.alertSuccess.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.colors.alertSuccess)
            )
    }

    var deviceId: some View {
        Text(deviceName)
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var description: some View {
        Text(NSLocalizedString("thisDevice", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.alertSuccess)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    ThisDevicePeerCell(deviceName: "iPhone", index: 1, totalCount: 3)
}
