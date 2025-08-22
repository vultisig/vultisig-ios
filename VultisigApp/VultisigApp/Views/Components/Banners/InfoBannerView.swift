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
    
    init(description: String, type: InfoBannerType, leadingIcon: String?) {
        self.description = description
        self.type = type
        self.leadingIcon = leadingIcon
    }
    
    
    var body: some View {
        HStack(spacing: 12) {
            if let leadingIcon {
                Icon(named: leadingIcon, color: fontColor, size: 12)
            }
            
            Text(description)
                .font(Theme.fonts.footnote)
                .foregroundStyle(fontColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bgColor)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    var fontColor: Color {
        switch type {
        case .info:
            Theme.colors.textLight
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
            Theme.colors.bgTertiary
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
