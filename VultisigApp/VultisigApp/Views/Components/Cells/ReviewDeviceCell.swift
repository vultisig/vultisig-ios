//
//  ReviewDeviceCell.swift
//  VultisigApp
//

import SwiftUI

struct ReviewDeviceCell: View {
    let id: String
    let index: Int
    var isThisDevice: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VaultSetupStepIcon(
                state: .active,
                icon: DeviceInfo.iconName(for: id)
            )

            VStack(alignment: .leading, spacing: 2) {
                title
                subtitle
            }

            Spacer()
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

    var title: some View {
        Group {
            if isThisDevice {
                Text("\(deviceName) ") +
                Text("(\(NSLocalizedString("thisDevice", comment: "").lowercased()))")
                    .foregroundColor(Theme.colors.textPrimary)
            } else {
                Text(deviceName)
            }
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundStyle(Theme.colors.textPrimary)
        .lineLimit(1)
    }

    var subtitle: some View {
        Text("\(NSLocalizedString("device", comment: "").capitalized) \(index) - \(deviceIDSuffix)")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
    }

    private var deviceName: String {
        let idString = id.lowercased()

        if idString.contains("mac") {
            return "Mac"
        } else if idString.contains("iphone") {
            return "iPhone"
        } else if idString.contains("ipad") {
            return "iPad"
        } else if idString.contains("server-") {
            return "Server"
        } else if idString.contains("extension-") {
            return "Extension"
        } else if idString.contains("windows-") {
            return "Windows"
        } else {
            return "Phone"
        }
    }

    private var deviceIDSuffix: String {
        if let lastDash = id.lastIndex(of: "-") {
            return String(id[id.index(after: lastDash)...])
        }
        return id
    }
}

#Preview {
    Screen {
        VStack {
            ReviewDeviceCell(id: "iPhone-ABC123", index: 1, isThisDevice: true)
            ReviewDeviceCell(id: "extension-ABC123", index: 2)
            ReviewDeviceCell(id: "MacBook Pro-ABC123", index: 3)
        }
        .padding(.horizontal, 16)
    }
}
