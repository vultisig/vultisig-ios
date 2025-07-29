//
//  SecurityScannerBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import SwiftUI

struct SecurityScannerBottomSheet: View {
    let securityScannerModel: SecurityScannerResult
    let onContinueAnyway: () -> Void
    let onDismissRequest: () -> Void
    
    var body: some View {
        let contentStyle = securityScannerModel.getSecurityScannerBottomSheetStyle()
        
        SecurityScannerBottomSheetContent(
            contentStyle: contentStyle,
            securityScannerProvider: securityScannerModel.provider,
            onDismissRequest: onDismissRequest,
            onContinueAnyway: onContinueAnyway
        )
        .background(Color.blue.opacity(0.1))
        .cornerRadius(24)
    }
}

struct SettingsSecurityScannerBottomSheet: View {
    let onContinueAnyway: () -> Void
    let onDismissRequest: () -> Void
    
    var body: some View {
        SecurityScannerBottomSheetContent(
            contentStyle: buildSettingsSecurityScannerBottomSheetStyle(),
            securityScannerProvider: nil,
            onDismissRequest: onDismissRequest,
            onContinueAnyway: onContinueAnyway
        )
        .background(Color.blue.opacity(0.1))
        .cornerRadius(24)
    }
}

struct SecurityScannerBottomSheetContent: View {
    let contentStyle: SecurityScannerBottomSheetStyle
    let securityScannerProvider: String?
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: contentStyle.image)
                .foregroundColor(contentStyle.imageColor)
                .font(.system(size: 32))
            
            Text(contentStyle.title)
                .foregroundColor(contentStyle.imageColor)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(contentStyle.description)
                .foregroundColor(.secondary)
                .font(.body)
                .multilineTextAlignment(.center)
            
            if let securityScannerProvider = securityScannerProvider {
                HStack {
                    Text("securityScannerPoweredBy".localized)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Image(getSecurityScannerLogo(securityScannerProvider))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 16)
                }
            }
            
            Button("securityScannerContinueGoBack".localized) {
                onDismissRequest()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            
            Button("securityScannerContinueAnyway".localized) {
                onContinueAnyway()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            
            Spacer()
                .frame(height: 16)
        }
        .padding(16)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }
}

extension SecurityScannerResult {
    func getSecurityScannerBottomSheetStyle() -> SecurityScannerBottomSheetStyle {
        let title: String
        switch riskLevel {
        case .medium:
            title = "securityScannerMediumRiskTitle".localized
        case .high:
            title = "securityScannerHighRiskTitle".localized
        case .critical:
            title = "securityScannerCriticalRiskTitle".localized
        case .none, .low:
            title = "securityScannerLowRiskTitle".localized
        }
        
        let description = self.description ?? "securityScannerDefaultDescription".localized
        let (color, icon) = if riskLevel == .critical || riskLevel == .high {
            (Color.red, "exclamationmark.triangle")
        } else {
            (Color.orange, "info.circle")
        }
        
        return SecurityScannerBottomSheetStyle(
            title: title,
            description: description,
            image: icon,
            imageColor: color
        )
    }
}

private func buildSettingsSecurityScannerBottomSheetStyle() -> SecurityScannerBottomSheetStyle {
    SecurityScannerBottomSheetStyle(
        title: "vault_settings_security_screen_title_bottomsheet".localized,
        description: "vault_settings_security_screen_content_bottomsheet".localized,
        image: "info.circle",
        imageColor: .orange
    )
}

struct SecurityScannerBottomSheetStyle {
    let title: String
    let description: String
    let image: String
    let imageColor: Color
}

private func getSecurityScannerLogo(_ provider: String) -> String {
    switch provider.lowercased() {
    case "blockaid":
        return "blockaid-logo"
    default:
        return "default-security-logo"
    }
}
