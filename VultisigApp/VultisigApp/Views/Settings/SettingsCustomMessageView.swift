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
    @State var method: String
    @State var message: String

    let vault: Vault
    let chain: String
    var autoSign: Bool
    var callbackUrl: String?
    private let fastVaultService = FastVaultService.shared

    @State private var fastVaultPassword: String = .empty
    @State private var fastPasswordPresented = false
    @State private var isFastVault = false

    @State private var autoSignPasswordPresented = false

    init(
        method: String = .empty,
        message: String = .empty,
        vault: Vault,
        chain: String,
        autoSign: Bool = false,
        callbackUrl: String? = nil
    ) {
        self._method = State(initialValue: method)
        self._message = State(initialValue: message)
        self.vault = vault
        self.chain = chain
        self.autoSign = autoSign
        self.callbackUrl = callbackUrl
    }

    var body: some View {
        ZStack {
            Background()
            main
        }
        .onLoad(perform: onLoad)
        .crossPlatformSheet(isPresented: $autoSignPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: {
                    onSignPress()
                }
            )
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
                                    chain: chain,
                                    callbackUrl: callbackUrl,
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
            isFastVault = await fastVaultService.isEligibleForFastSign(vault: vault)
            if autoSign && !method.isEmpty && !message.isEmpty {
                if isFastVault {
                    autoSignPasswordPresented = true
                } else {
                    viewModel.moveToNextView()
                }
            }
        }
    }

    func onSignPress() {
        viewModel.moveToNextView()
    }
}
