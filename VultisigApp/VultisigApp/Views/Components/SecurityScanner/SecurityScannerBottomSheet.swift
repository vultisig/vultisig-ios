//
//  SecurityScannerBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import SwiftUI

struct SecurityScannerBottomSheet: View & BottomSheetProperties {
    let securityScannerModel: SecurityScannerResult?
    let onContinueAnyway: () -> Void
    let onDismissRequest: () -> Void
    
    var body: some View {
        if let securityScannerModel {
            let contentStyle = securityScannerModel.getSecurityScannerBottomSheetStyle()
            SecurityScannerBottomSheetContent(
                contentStyle: contentStyle,
                securityScannerProvider: securityScannerModel.provider,
                onDismissRequest: onDismissRequest,
                onContinueAnyway: onContinueAnyway
            )
        }
    }
}

struct SecurityScannerBottomSheetContent: View {
    let contentStyle: SecurityScannerBottomSheetStyle
    let securityScannerProvider: String?
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: contentStyle.image)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(contentStyle.imageColor)
                
            VStack(spacing: 12) {
                Text(contentStyle.title)
                    .foregroundColor(contentStyle.imageColor)
                    .font(.body22BrockmannMedium)
                    .multilineTextAlignment(.center)
                
                Text(contentStyle.description)
                    .foregroundStyle(Color.extraLightGray)
                    .font(.body14BrockmannMedium)
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
            }
            
            if let securityScannerProvider = securityScannerProvider {
                HStack(spacing: 4) {
                    Spacer()
                    Text("securityScannerPoweredBy".localized)
                        .foregroundStyle(Color.extraLightGray)
                        .font(.body14BrockmannMedium)
                    Image(securityScannerProvider)
                        .foregroundStyle(Color.extraLightGray)
                    Spacer()
                }
            }
            
            VStack(spacing: 8) {
                PrimaryButton(title: "securityScannerContinueGoBack".localized) {
                    onDismissRequest()
                }
                
                Button("securityScannerContinueAnyway".localized) {
                    onContinueAnyway()
                }
                .frame(height: 42, alignment: .center)
                .foregroundStyle(Color.textDisabled)
                .font(.body10BrockmannMedium)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsSecurityScannerBottomSheet: View, BottomSheetProperties {
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void
    var body: some View {
        SecurityScannerBottomSheetContent(
            contentStyle: SecurityScannerBottomSheetStyle(
                title: "vaultSettingsSecurityScreenTitleBottomsheet".localized,
                description: "vaultSettingsSecurityScreenContentBottomsheet".localized,
                image: "exclamationmark.circle",
                imageColor: Color.alertYellow
            ),
            securityScannerProvider: nil,
            onDismissRequest: onDismissRequest,
            onContinueAnyway: onContinueAnyway
        )
    }
}

private extension SecurityScannerResult {
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
            (Color.invalidRed, "exclamationmark.triangle")
        } else {
            (Color.alertYellow, "exclamationmark.circle")
        }
        
        return SecurityScannerBottomSheetStyle(
            title: title,
            description: description,
            image: icon,
            imageColor: color
        )
    }
}

struct SecurityScannerBottomSheetStyle {
    let title: String
    let description: String
    let image: String
    let imageColor: Color
}


