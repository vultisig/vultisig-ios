//
//  PeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-04.
//

import SwiftUI

struct PeerCell: View {
    let id: String
    let isSelected: Bool
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
        .padding(16)
        .background(isSelected ? Theme.colors.bgSuccess : Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected ? Theme.colors.alertSuccess.opacity(0.25) : Theme.colors.border,
                    lineWidth: 1
                )
        )
        .padding(1)
    }

    var deviceIcon: some View {
        Circle()
            .fill(
                isSelected
                    ? Theme.colors.alertSuccess.opacity(0.15)
                    : Theme.colors.bgSurface2
            )
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        isSelected
                            ? Theme.colors.alertSuccess
                            : Theme.colors.textTertiary
                    )
            )
    }

    var deviceId: some View {
        Text(getDeviceName())
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var description: some View {
        Group {
            if isSelected {
                Text(NSLocalizedString("connected", comment: ""))
                    .foregroundStyle(Theme.colors.alertSuccess)
            } else {
                Text(id)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
        .font(Theme.fonts.caption12)
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

    private func getDeviceName() -> String {
        let idString = id.lowercased()
        let deviceName: String

        if idString.contains("mac") {
            deviceName = "Mac"
        } else if idString.contains("iphone") {
            deviceName = "iPhone"
        } else if idString.contains("ipad") {
            deviceName = "iPad"
        } else if idString.contains("server-") {
            deviceName = "Server"
        } else if idString.contains("extension-") {
            deviceName = "Extension"
        } else if idString.contains("windows-") {
            deviceName = "Windows"
        } else {
            deviceName = "Phone"
        }
        return deviceName
    }
}

#Preview {
    VStack {
        PeerCell(id: "iPhone 15 Pro-5D2F5D984A37", isSelected: true, index: 2, totalCount: 3)
        PeerCell(id: "iPad 15 Pro-5D2F5D984A37", isSelected: false, index: 3, totalCount: 3)
    }
}
