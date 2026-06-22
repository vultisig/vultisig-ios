//
//  SettingsCustomMessageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.12.2024.
//

import SwiftUI

struct SettingsCustomMessageView: View {

    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var appViewModel: AppViewModel

    @StateObject var viewModel = SettingsCustomMessageViewModel()

    @State var keysignView: KeysignView?
    @State var method: String = .empty
    @State var message: String = .empty

    @State var fastVaultPassword: String = .empty
    @State var fastPasswordPresented = false

    let vault: Vault
    private let fastVaultService = FastVaultService.shared

    var body: some View {
        ZStack {
            Background()
            main
        }
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
            case .verify:
                verify
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
                continueButton
                    .padding(.bottom, isMacOS ? 40 : 0)
            }
        }
    }

    var verify: some View {
        ScrollView {
            verifyContent
                .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.state == .verify {
                signButton
                    .padding(.bottom, isMacOS ? 40 : 0)
            }
        }
    }

    var verifyContent: some View {
        VStack(spacing: 16) {
            verifyRow(title: "signingMethod".localized, value: method)
            verifyRow(title: "messageToSign".localized, value: message)
        }
        .padding(.top, 12)
    }

    private func verifyRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.colors.bgSurface2)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                signingErrorView
            }
        }
    }

    var signingErrorView: some View {
        let presentation = ErrorPresentation.signing(rawError: message)
        return ErrorView(
            type: presentation.type,
            title: presentation.title,
            description: presentation.description,
            buttonTitle: "tryAgain".localized,
            rawError: presentation.rawError
        ) {
            appViewModel.restart()
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
        PairScreen(
            vault: vault,
            customMessagePayload: customMessagePayload,
            fastVaultPassword: fastVaultPassword.nilIfEmpty,
            title: viewModel.state.title,
            isShareButtonVisible: !vault.isFastVault
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

    var continueButton: some View {
        PrimaryButton(title: NSLocalizedString("continue", comment: "")) {
            viewModel.moveToNextView()
        }
        .disabled(!signButtonEnabled)
        .padding(.horizontal, 16)
    }

    var signButton: some View {
        SigningCTAButtons(
            isFastVault: vault.isFastVault,
            isDisabled: !signButtonEnabled,
            singleSignTitle: "signTransaction",
            onFastSign: { fastPasswordPresented = true },
            onPairedSign: {
                fastVaultPassword = .empty
                onSignPress()
            }
        )
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { onSignPress() }
            )
        }
        .padding(.horizontal, 16)
    }

    func onSignPress() {
        viewModel.moveToNextView()
    }
}
