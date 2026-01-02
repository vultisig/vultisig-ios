//
//  FastVaultPasswordDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-30.
//

import SwiftUI

struct FastVaultPasswordDisclaimer: View {
    @Binding var showTooltip: Bool
    
    var body: some View {
        VStack {
            content
            tooltip
        }
    }
    
    var content: some View {
        HStack {
            text
            Spacer()
            info
        }
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.alertWarning)
        .padding(16)
        .background(Theme.colors.bgAlert)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.alertWarning.opacity(0.25), lineWidth: 1)
        )
    }
    
    var text: some View {
        Text(NSLocalizedString("PasswordCannotBeReset", comment: ""))
    }
    
    var info: some View {
        Button {
            showTooltip.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
    }
    
    var tooltip: some View {
        VStack(spacing: 0) {
            arrow
            bubble
        }
        .opacity(showTooltip ? 1 : 0)
        .frame(maxHeight: showTooltip ? nil : 0)
        .animation(.easeInOut, value: showTooltip)
        .clipped()
    }
    
    var arrow: some View {
        HStack {
            Spacer()
            
            Image("TooltipArrow")
                .resizable()
                .frame(width: 37, height: 12)
                .offset(x: -12)
        }
    }
    
    var bubble: some View {
        VStack(spacing: 8) {
            title
            description
        }
        .padding(16)
        .background(Theme.colors.textSecondary)
        .cornerRadius(12)
    }
    
    var title: some View {
        HStack {
            Text(NSLocalizedString("moreInfo", comment: ""))
                .foregroundColor(Theme.colors.textDark)
            
            Spacer()
            closeButton
        }
        .font(Theme.fonts.bodyMMedium)
    }
    
    var closeButton: some View {
        Button {
            showTooltip = false
        } label: {
            Image(systemName: "xmark")
                .foregroundColor(Theme.colors.textButtonDisabled)
        }
    }
    
    var description: some View {
        Text(NSLocalizedString("moreInfoDescription", comment: ""))
            .foregroundColor(Theme.colors.textTertiary)
            .font(Theme.fonts.bodySMedium)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity,alignment: .leading)
    }
}

#Preview {
    FastVaultPasswordDisclaimer(showTooltip: .constant(false))
}
