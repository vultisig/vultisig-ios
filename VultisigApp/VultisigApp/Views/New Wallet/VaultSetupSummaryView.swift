//
//  VaultSetupSummaryView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-03.
//

import SwiftUI

struct VaultSetupSummaryView: View {
    let vault: Vault
    
    @State var didAgree = false
    @State var isFastVault = false
    @State var isLinkActive = false
    
    @State var contentHeight: CGFloat = .zero
    @State var cellHeight: CGFloat = .zero
    
    var body: some View {
        container
            .navigationDestination(isPresented: $isLinkActive) {
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
            }
            .onAppear {
                isFastVault = vault.isFastVault
            }
    }
    
    var main: some View {
        HStack(spacing: 0) {
            rectangle
            VStack(spacing: 16) {
                Spacer()
                content
                Spacer()
                disclaimer
                button
            }
        }
        .padding(24)
    }
    
    var rectangle: some View {
        Rectangle()
            .frame(width: 2, height: contentHeight-cellHeight+6)
            .foregroundColor(.blue600)
            .offset(y: -50)
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
                .stroke(Color.blue200, lineWidth: 1)
        )
        .offset(x: -2)
    }
    
    var icon: some View {
        Image(systemName: isFastVault ? "bolt" : "shield")
            .foregroundColor(isFastVault ? .alertYellow : .alertTurquoise)
    }
    
    var text: some View {
        Text(NSLocalizedString(isFastVault ? "fastVault" : "secureVault", comment: ""))
            .foregroundColor(.extraLightGray)
            .font(.body12BrockmannMedium)
    }
    
    var title: some View {
        Text(NSLocalizedString("backupGuide", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body34BrockmannMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
    }
    
    var list: some View {
        ZStack {
            if isFastVault {
                fastVaultList
            } else {
                secureVaultList
            }
        }
    }
    
    var fastVaultList: some View {
        VStack(spacing: 16) {
            getCell(icon: "envelope", text: "fastVaultSummaryText1")
            getCell(icon: "checkmark.icloud", text: "fastVaultSummaryText2")
            getCell(icon: "arrow.trianglehead.branch", text: "fastVaultSummaryText3")
            getCell(icon: "square.3.layers.3d", text: "fastVaultSummaryText4")
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
    
    var secureVaultList: some View {
        let secureVaultSummaryText1 = "Your vault has \(vault.signers.count) Vault Shares"
        
        return VStack(spacing: 16) {
            getCell(icon: "info.circle", text: secureVaultSummaryText1)
            getCell(icon: "checkmark.icloud", text: "secureVaultSummaryText2")
            getCell(icon: "arrow.trianglehead.branch", text: "secureVaultSummaryText3")
            getCell(icon: "square.3.layers.3d", text: "secureVaultSummaryText4")
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
    
    var disclaimer: some View {
        Button {
            withAnimation {
                didAgree.toggle()
            }
        } label: {
            disclaimerLabel
        }
    }
    
    var disclaimerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: didAgree ? "checkmark.circle" : "circle")
                .foregroundColor(.alertTurquoise)
            
            Text(NSLocalizedString("secureVaultSummaryDiscalimer", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14BrockmannMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }
    
    var button: some View {
        Button {
            isLinkActive = true
        } label: {
            FilledButton(
                title: "startUsingVault",
                textColor: didAgree ? .blue600 : .textDisabled,
                background: didAgree ? .turquoise600 : .buttonDisabled
            )
        }
        .disabled(!didAgree)
    }
    
    private func getCell(icon: String, text: String) -> some View {
        HStack(spacing: 0){
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundColor(.blue600)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.iconLightBlue)
                
                Text(NSLocalizedString(text, comment: ""))
                    .foregroundColor(.neutral0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body14BrockmannMedium)
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue200, lineWidth: 1)
            )
        }
    }
}

#Preview {
    VaultSetupSummaryView(vault: Vault.fastVaultExample)
}
