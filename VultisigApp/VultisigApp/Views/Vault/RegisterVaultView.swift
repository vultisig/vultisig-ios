//
//  RegisterVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

import SwiftUI

struct RegisterVaultView: View {
    let vault: Vault

    @StateObject var viewModel = VaultDetailQRCodeViewModel()

    @State var imageName = ""
    @State var isExporting: Bool = false

    @Environment(\.displayScale) var displayScale

    var body: some View {
        Screen(title: "registerVault".localized) {
            VStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Image("register-vault")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 250)
                            .background(
                                EllipticalGradient(
                                    stops: [
                                        Gradient.Stop(color: Color(red: 0.2, green: 0.9, blue: 0.75).opacity(0.52), location: 0.00),
                                        Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
                                    ],
                                    center: UnitPoint(x: 0.5, y: 0.5)
                                )
                                .blur(radius: 50)
                                .offset(y: 30)
                            )
                            .padding(.top, 30)
                        StepsAnimationView(
                            title: "registerGuide".localized,
                            steps: 4
                        ) { animationCell(for: $0) }
                    }
                }
                saveVaultButton
            }
        }
        .onLoad(perform: setData)
    }

    @ViewBuilder
    func animationCell(for index: Int) -> some View {
        let attrString = text(for: index)
        switch index {
        case 0:
            commonCell(icon: "qr-code", title: attrString)
        case 1:
            Link(destination: StaticURL.VultisigAirdropWeb) {
                commonCell(icon: "app-window", title: attrString + websiteText)
            }
        case 2:
            commonCell(icon: "upload", title: attrString)
        case 3:
            commonCell(icon: "coins", title: attrString)
        default:
            EmptyView()
        }
    }

    func text(for index: Int) -> AttributedString {
        var attrString = AttributedString("registerVaultText\(index + 1)".localized)
        attrString.font = Theme.fonts.footnote
        attrString.foregroundColor = Theme.colors.textPrimary
        return attrString
    }

    var websiteText: AttributedString {
        var attrString = AttributedString("Vultisig Web")
        attrString.font = Theme.fonts.footnote
        attrString.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.colors.alertSuccess)
        attrString.foregroundColor = Theme.colors.alertSuccess
        return attrString
    }

    func commonCell(icon: String, title: AttributedString) -> some View {
        HStack(spacing: 12) {
            Icon(named: icon, size: 24)
            Text(title)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setData() {
        imageName = viewModel.generateName(vault: vault)
        viewModel.render(vault: vault, displayScale: displayScale)
    }
}

#Preview {
    RegisterVaultView(vault: Vault.example)
}
