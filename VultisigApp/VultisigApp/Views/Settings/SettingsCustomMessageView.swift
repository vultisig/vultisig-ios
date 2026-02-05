//
//  SettingsCustomMessageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.12.2024.
//

import SwiftUI

struct SettingsCustomMessageView: View {

    @Environment(\.dismiss) var dismiss

    @StateObject var viewModel = SettingsCustomMessageViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State var keysignView: KeysignView?
    @State var method: String = .empty
    @State var message: String = .empty

    @State var fastVaultPassword: String = .empty
    @State var fastPasswordPresented = false
    @State var isFastVault = false

    let vault: Vault
    private let fastVaultService = FastVaultService.shared

    var body: some View {
        ZStack {
            Background()
            main
        }
        .onLoad(perform: onLoad)
    }

    var view: some View {
        VStack(spacing: 18) {
            tabView
        }
    }

    var tabView: some View {
        ZStack {
            switch viewModel.state {
            case .initial:
                customMessage
            case .pair:
                pair
            case .keysign, .done:
                keysign
            }
        }
    }

    var customMessage: some View {
        ScrollView {
            customMessageContent
                .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.state == .initial {
                signButton
                    .padding(.bottom, isMacOS ? 40 : 0)
            }
        }
    }

    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                SendCryptoSigningErrorView(errorString: message)
            }
        }
    }

    func title(text: String) -> some View {
        HStack {
            Text(text)
                .font(Theme.fonts.bodySRegular)
                .foregroundColor(.white)

            Spacer()
        }
    }

    func textField(title: String, text: Binding<String>) -> some View {
        CommonTextField(text: text, placeholder: title)
    }

    var pair: some View {
        KeysignDiscoveryView(
            vault: vault,
            keysignPayload: nil,
            customMessagePayload: customMessagePayload,
            fastVaultPassword: fastVaultPassword.nilIfEmpty,
            shareSheetViewModel: shareSheetViewModel
        ) { input in
            self.keysignView = KeysignView(
                vault: input.vault,
                keysignCommittee: input.keysignCommittee,
                mediatorURL: input.mediatorURL,
                sessionID: input.sessionID,
                keysignType: input.keysignType,
                messsageToSign: input.messsageToSign,
                keysignPayload: input.keysignPayload,
                customMessagePayload: input.customMessagePayload,
                transferViewModel: viewModel,
                encryptionKeyHex: input.encryptionKeyHex,
                isInitiateDevice: input.isInitiateDevice
            )
            viewModel.moveToNextView()
        }
        .crossPlatformToolbar(viewModel.state.title) {
            CustomToolbarItem(placement: .trailing) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
                .showIf(!isFastVault)
            }
        }
    }

    var backButton: some View {
        return Button {
            viewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(viewModel.state == .done ? 0 : 1)
        .disabled(viewModel.state == .done)
    }

    var signButtonEnabled: Bool {
        return !method.isEmpty && !message.isEmpty
    }

    var customMessagePayload: CustomMessagePayload? {
        return CustomMessagePayload(method: method,
                                    message: message,
                                    vaultPublicKeyECDSA: vault.pubKeyECDSA,
                                    vaultLocalPartyID: vault.localPartyID,
                                    chain: Chain.ethereum.name,
                                    decodedMessage: nil)
    }

    @ViewBuilder
    var signButton: some View {
        VStack(spacing: 16) {
            if isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)

                LongPressPrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    onSignPress()
                }
                .disabled(!signButtonEnabled)
                .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $fastVaultPassword,
                        vault: vault,
                        onSubmit: { onSignPress() }
                    )
                }
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    onSignPress()
                }
                .disabled(!signButtonEnabled)
            }
        }
        .padding(.horizontal, 16)
    }

    func onLoad() {
        Task { @MainActor in
            let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
            let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
            isFastVault = isExist && !isLocalBackup
        }
    }

    func onSignPress() {
        viewModel.moveToNextView()
    }
}
