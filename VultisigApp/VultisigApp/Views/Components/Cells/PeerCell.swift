//
//  PeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-04.
//

import SwiftUI

struct PeerCell: View {
    let id: String
    var isSelected: Bool = false
    var isThisDevice: Bool = false
    var index: Int? = nil
    var totalCount: Int? = nil

    private var isHighlighted: Bool {
        isThisDevice || isSelected
    }

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
    }

    var deviceIcon: some View {
        Circle()
            .fill(Theme.colors.alertSuccess.opacity(0.05))
            .stroke(Theme.colors.alertSuccess, lineWidth: 1.5)
            .frame(width: 32, height: 32)
            .overlay(
                Icon(
                    named: DeviceInfo.iconName(for: id),
                    color: Theme.colors.alertSuccess,
                    size: 16
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
            if isThisDevice {
                Text(NSLocalizedString("thisDevice", comment: ""))
                    .foregroundStyle(Theme.colors.alertSuccess)
            } else if isSelected {
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

    private func badge(index: Int, totalCount: Int?) -> some View {
        Text(String(format: NSLocalizedString("nOfTotal", comment: ""), index, totalCount.map { "\($0)" } ?? "\u{221E}"))
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
        PeerCell(id: "iPhone", isThisDevice: true, index: 1, totalCount: 3)
        PeerCell(id: "MacBook Pro-5D2F5D984A37", isSelected: true, index: 2, totalCount: 3)
        PeerCell(id: "iPad 15 Pro-5D2F5D984A37", index: 3, totalCount: 3)
    }
}
