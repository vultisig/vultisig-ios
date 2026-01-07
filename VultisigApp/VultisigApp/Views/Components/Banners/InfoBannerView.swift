//
//  Banner.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 19/08/2025.
//

import SwiftUI

enum InfoBannerType {
    case info
    case warning
    case error
    case success
}

struct InfoBannerView: View {
    let description: String
    let type: InfoBannerType
    let leadingIcon: String?
    let iconColor: Color?
    let onClose: (() -> Void)?
    
    init(description: String, type: InfoBannerType, leadingIcon: String?, iconColor: Color? = nil, onClose: (() -> Void)? = nil) {
        self.description = description
        self.type = type
        self.leadingIcon = leadingIcon
        self.iconColor = iconColor
        self.onClose = onClose
    }
    
    
    var body: some View {
        HStack(spacing: 12) {
            if let leadingIcon {
                Icon(named: leadingIcon, color: iconColor ?? fontColor, size: 16)
            }
            
            Text(description)
                .font(Theme.fonts.footnote)
                .foregroundStyle(fontColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            if let onClose {
                Spacer()
                Button(action: onClose) {
                    Icon(named: "x", color: Theme.colors.textSecondary, size: 12)
                        .padding(8)
                        .background(Circle().fill(Theme.colors.bgSurface2))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 1)
                .fill(bgColor)
                .stroke(borderColor, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
    
    var fontColor: Color {
        switch type {
        case .info:
            Theme.colors.textSecondary
        case .warning:
            Theme.colors.alertWarning
        case .error:
            Theme.colors.alertError
        case .success:
            Theme.colors.alertSuccess
        }
    }
    
    var bgColor: Color {
        switch type {
        case .info:
            Theme.colors.bgNeutral
        case .warning:
            Theme.colors.bgAlert
        case .error:
            Theme.colors.bgError
        case .success:
            Theme.colors.bgSuccess
        }
    }
    
    var borderColor: Color {
        switch type {
        case .info:
            Theme.colors.bgSurface2
        case .warning:
            Theme.colors.alertWarning.opacity(0.35)
        case .error:
            Theme.colors.alertError.opacity(0.35)
        case .success:
            Theme.colors.bgSuccess.opacity(0.35)
        }
    }
}

#Preview {
    InfoBannerView(description: "This is a test", type: .info, leadingIcon: nil)
}
