//
//  VaultPairDetailCard.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI
import VultisigUIResources

struct VaultPairDetailCard: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]
    let isForSharing: Bool
    let onKeyCopy: (() -> Void)?

    @State var deviceIndex: Int = 0

    private static let rowMinHeight: CGFloat = 66
    private static let signerTextMinHeight: CGFloat = 58

    init(vault: Vault, devicesInfo: [DeviceInfo], isForSharing: Bool = false, onKeyCopy: (() -> Void)? = nil) {
        self.vault = vault
        self.devicesInfo = devicesInfo
        self.isForSharing = isForSharing
        self.onKeyCopy = onKeyCopy
    }

    var body: some View {
        VStack(spacing: 24) {
            if isForSharing {
                // Header for sharing
                VultisigImage("vultisig-logo")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.top, 24)
            }

            vaultInfoSection
            vaultKeysSection
            vaultSetupSection

            if isForSharing {
                // Footer for sharing
                Text("vultisig.com")
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.bottom, 24)
            }
        }
        .padding(isForSharing ? 24 : 0)
        .background(isForSharing ? Theme.colors.bgPrimary : Color.clear)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: isForSharing)
    }

    var vaultInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("vaultInfo".localized)

            vaultInfoRow(title: "vaultName".localized, description: vault.name)
            vaultInfoRow(title: "vaultPart".localized, description: titlePartText())
            vaultInfoRow(title: "vaultLibType".localized, description: getVaultLibType())
        }
    }

    var vaultKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("keys".localized)

            vaultKeyRow(title: "ECDSAKey".localized, description: vault.pubKeyECDSA)
            vaultKeyRow(title: "EdDSAKey".localized, description: vault.pubKeyEdDSA)

            if let publicKeyMLDSA44 = vault.publicKeyMLDSA44, !publicKeyMLDSA44.isEmpty {
                vaultKeyRow(title: "MLDSA".localized, description: publicKeyMLDSA44)
            }
        }
    }

    @ViewBuilder
    var vaultSetupSection: some View {
        let title = String(format: "vaultSetupThreshold".localized, vault.getThreshold() + 1, devicesInfo.count)
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(devicesInfo, id: \.Index) { device in
                    signerCell(for: device)
                }
            }
        }
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .settingsText(.caption)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    func vaultInfoRow(title: String, description: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(description)
        }
        .settingsText(.bodyS)
        .foregroundStyle(Theme.colors.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: Self.rowMinHeight)
        .settingsInfoCard()
    }

    func vaultKeyRow(title: String, description: String) -> some View {
        Button {
            if !isForSharing {
                ClipboardManager.copyToClipboard(description)
                onKeyCopy?()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .settingsText(.subtitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(description)
                        .settingsText(.caption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isForSharing {
                    Icon(.copies3Filled, color: Theme.colors.textPrimary, size: 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: Self.rowMinHeight)
            .settingsInfoCard()
            .contentShape(Theme.radius.md.shape)
        }
        .disabled(isForSharing)
    }

    @ViewBuilder
    func signerCell(for device: DeviceInfo) -> some View {
        let signer = device.Signer
        let isLocalPary = device.Signer == vault.localPartyID
        let signerTitle = "\("signer".localized) \(device.Index + 1)"

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(signerTitle)
                    .settingsText(.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)

                Text(signer)
                    .settingsText(.buttonS)
                    .foregroundStyle(.white)

                Text("vaultDetailsThisDevice".localized)
                    .settingsText(.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .showIf(isLocalPary)
            }
            .frame(maxWidth: .infinity, minHeight: Self.signerTextMinHeight, alignment: .leading)
            Icon(
                iconName(for: signer),
                color: Theme.colors.textTertiary,
                size: 23
            )
        }
        .padding(16)
        .settingsInfoCard(radius: Theme.radius.lg)
        .onLoad {
            if isLocalPary {
                deviceIndex = device.Index + 1
            }
        }
    }

    private func getVaultLibType() -> String {
        guard let libType = vault.libType else {
            return "GG20"
        }
        switch libType {
        case .DKLS:
            return "DKLS"
        case .GG20:
            return "GG20"
        case .KeyImport:
            return "DKLS-Imported"
        }
    }

    private func titlePartText() -> String {
        let matchedIndex = devicesInfo.first(where: { $0.Signer == vault.localPartyID })?.Index
        let vaultIndex = matchedIndex.map { $0 + 1 } ?? 0
        return String(format: "vaultSharePosition".localized, vaultIndex, vault.signers.count)
    }

    func iconName(for signer: String) -> ImageResource {
        DeviceInfo.iconName(for: signer)
    }
}

#Preview {
    VaultPairDetailCard(vault: Vault.example, devicesInfo: [])
}
