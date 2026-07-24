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
    /// The keysign ceremony view-model, owned here so this host can crossfade
    /// the shared KeysignView animation to the signed-message done surface once
    /// signing finishes — the same pattern as the initiator and cosigner.
    @StateObject private var keysignVM = KeysignViewModel()

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
                .foregroundStyle(Theme.colors.textTertiary)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
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
            if keysignVM.status == .KeysignFinished {
                JoinKeysignDoneView(vault: vault, viewModel: keysignVM)
                    .transition(.opacity)
            } else {
                keysignSigning
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: keysignVM.status == .KeysignFinished)
        .onChange(of: keysignVM.status) { _, status in
            // Advance the flow state on finish (title -> "overview", back button
            // hidden), matching the former KeysignView-driven moveToNextView.
            if status == .KeysignFinished, viewModel.state == .keysign {
                viewModel.moveToNextView()
            }
        }
    }

    var keysignSigning: some View {
        ZStack {
            if let fastPassword = fastVaultPassword.nilIfEmpty {
                // Fast vaults skip the pair screen: KeysignView runs the
                // off-screen relay bootstrap itself (connecting animation) and
                // then drives the signing ceremony.
                KeysignView(
                    viewModel: keysignVM,
                    source: .fast(
                        vault: vault,
                        keysignPayload: nil,
                        customMessagePayload: customMessagePayload,
                        fastVaultPassword: fastPassword
                    )
                )
            } else if let keysignView = keysignView {
                keysignView
            } else {
                signingErrorView
            }
        }
    }

    var signingErrorView: some View {
        // `keysignView` is only nil here as a defensive fallback (it's set in the
        // pair callback immediately before advancing to this state), so there's no
        // captured signing error to show — present a generic failure rather than
        // leaking the user's custom message as the error.
        let presentation = ErrorPresentation.signing(rawError: "")
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
                .foregroundStyle(.white)

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
                viewModel: keysignVM,
                vault: input.vault,
                keysignCommittee: input.keysignCommittee,
                mediatorURL: input.mediatorURL,
                sessionID: input.sessionID,
                keysignType: input.keysignType,
                messsageToSign: input.messsageToSign,
                keysignPayload: input.keysignPayload,
                customMessagePayload: input.customMessagePayload,
                encryptionKeyHex: input.encryptionKeyHex,
                isInitiateDevice: input.isInitiateDevice
            )
            viewModel.moveToNextView()
        }
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
        // Fast vaults have no peer to pair with, so skip the pair state and
        // land on keysign, where the off-screen bootstrap runs. A present
        // fast password is the fast-sign signal; paired-sign (empty
        // password) keeps the pair state and its QR screen. Advancing to
        // keysign also hides the back button during signing (canGoBack()).
        if fastVaultPassword.nilIfEmpty != nil {
            viewModel.moveToNextView()
        }
    }
}
