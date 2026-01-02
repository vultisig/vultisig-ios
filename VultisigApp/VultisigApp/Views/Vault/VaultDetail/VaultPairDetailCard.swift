//
//  VaultPairDetailCard.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct VaultPairDetailCard: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]
    let isForSharing: Bool
    let onKeyCopy: (() -> Void)?

    @State var deviceIndex: Int = 0

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
                Image("VultisigLogo")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .foregroundColor(Theme.colors.textPrimary)
                    .padding(.top, 24)
            }

            vaultInfoSection
            vaultKeysSection
            vaultSetupSection

            if isForSharing {
                // Footer for sharing
                Text("vultisig.com")
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundColor(Theme.colors.textPrimary)
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
            Text("vaultInfo".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            vaultInfoRow(title: "vaultName".localized, description: vault.name)
            vaultInfoRow(title: "vaultPart".localized, description: titlePartText())
            vaultInfoRow(title: "vaultLibType".localized, description: getVaultLibType())
        }
    }

    var vaultKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("keys".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            vaultKeyRow(title: "ECDSA".localized, description: vault.pubKeyECDSA)
            vaultKeyRow(title: "EdDSA".localized, description: vault.pubKeyEdDSA)
        }
    }

    @ViewBuilder
    var vaultSetupSection: some View {
        let title = "\(vault.getThreshold()+1)-\("of".localized)-\(devicesInfo.count) " + "vaultSetup".localized
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

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

    func vaultInfoRow(title: String, description: String) -> some View {
        ContainerView {
            HStack {
                Text(title)
                Spacer()
                Text(description)
            }
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.vertical, 4)
        }
    }

    func vaultKeyRow(title: String, description: String) -> some View {
        Button {
            if !isForSharing {
                ClipboardManager.copyToClipboard(description)
                onKeyCopy?()
            }
        } label: {
            ContainerView {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text(description)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    if !isForSharing {
                        Icon(named: "copy", color: Theme.colors.textPrimary, size: 17)
                    }
                }
            }
        }
        .disabled(isForSharing)
    }

    @ViewBuilder
    func signerCell(for device: DeviceInfo) -> some View {
        let signer = device.Signer
        let isLocalPary = device.Signer == vault.localPartyID
        let signerTitle = "\("signer".localized) \(device.Index + 1)"

        ContainerView {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(signerTitle)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text(signer)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text("thisDevice".localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .showIf(isLocalPary)
                }
                Spacer()
                Icon(
                    named: iconName(for: signer),
                    color: Theme.colors.textTertiary,
                    size: 24
                )
            }
            .frame(maxWidth: .infinity, maxHeight: 75, alignment: .center)
            .onLoad {
                if isLocalPary {
                    deviceIndex = device.Index + 1
                }
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
        let part = NSLocalizedString("share", comment: "")
        let of = NSLocalizedString("of", comment: "")
        let space = " "
        let vaultIndex = "\(deviceIndex)"
        let totalCount = "\(vault.signers.count)"

        return part + space + vaultIndex + space + of + space + totalCount
    }

    func iconName(for signer: String) -> String {
        let laptopSigners = ["windows", "extension", "mac"]
        let isLaptoSigner = laptopSigners.contains {
            signer.lowercased().contains($0)
        }

        return isLaptoSigner ? "laptop" : "smartphone"
    }
}

#Preview {
    VaultPairDetailCard(vault: Vault.example, devicesInfo: [])
}
