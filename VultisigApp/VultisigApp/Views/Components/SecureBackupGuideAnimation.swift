//
//  SecureBackupGuideAnimation.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-14.
//

import SwiftUI

struct SecureBackupGuideAnimation: View {
    let vault: Vault?

    @State var contentHeight: CGFloat = .zero
    @State var cellHeight: CGFloat = .zero
    
    @State var showCell1: Bool = false
    @State var showCell2: Bool = false
    @State var showCell3: Bool = false
    @State var showCell4: Bool = false

    var body: some View {
        ZStack {
            Background()
            main
        }
    }

    var main: some View {
        HStack(spacing: 0) {
            rectangle
            content
        }
        .padding(24)
    }

    var rectangle: some View {
        Rectangle()
            .frame(width: 2, height: contentHeight-cellHeight+6)
            .foregroundColor(.blue600)
            .offset(y: -2)
    }

    var content: some View {
        VStack(spacing: 28) {
            headerContent
            title
            list
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        contentHeight = geometry.size.height
                        setData()
                    }
            }
        )
    }

    var headerContent: some View {
        HStack {
            header
            Spacer()
        }
    }

    var header: some View {
        HStack {
            icon
            text
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .offset(x: -2)
    }

    var icon: some View {
        Image(systemName: "shield")
            .foregroundColor(.alertTurquoise)
    }

    var text: some View {
        Text(NSLocalizedString("secureVault", comment: ""))
            .foregroundColor(.extraLightGray)
            .font(Theme.fonts.caption12)
    }

    var title: some View {
        Text(NSLocalizedString("backupGuide", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.largeTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
    }

    var list: some View {
        let secureVaultSummaryText1 = "Your vault has \(vault?.signers.count ?? 0) Vault Shares"

        return VStack(spacing: 16) {
            getCell(icon: "info.circle", text: secureVaultSummaryText1, showCell: showCell1)
            getCell(icon: "checkmark.icloud", text: "secureVaultSummaryText2", showCell: showCell2)
            getCell(icon: "arrow.trianglehead.branch", text: "secureVaultSummaryText3", showCell: showCell3)
            getCell(icon: "square.3.layers.3d", text: "secureVaultSummaryText4", showCell: showCell4)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                cellHeight = geometry.size.height
                            }
                    }
                )
        }
    }

    private func getCell(icon: String, text: String, showCell: Bool) -> some View {
        HStack(spacing: 0){
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundColor(.blue600)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.iconLightBlue)

                Text(NSLocalizedString(text, comment: ""))
                    .foregroundColor(Theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.fonts.bodySMedium)
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
        }
        .opacity(showCell ? 1 : 0)
        .offset(y: showCell ? 0 : -10)
        .animation(.easeInOut, value: showCell)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showCell1 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showCell2 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showCell3 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showCell4 = true
        }
    }
}

#Preview {
    SecureBackupGuideAnimation(vault: Vault.example)
}
