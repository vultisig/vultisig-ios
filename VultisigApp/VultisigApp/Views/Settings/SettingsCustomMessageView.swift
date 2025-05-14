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

    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            main
        }
    }

    var view: some View {
        VStack(spacing: 18) {
            ProgressBar(progress: viewModel.progress)
                .padding(.top, 12)

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
                button
            }
        }
    }

    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                SendCryptoSigningErrorView()
            }
        }
    }

    func title(text: String) -> some View {
        HStack {
            Text(text)
                .font(.body14Montserrat)
                .foregroundColor(.white)

            Spacer()
        }
    }

    func textField(title: String, text: Binding<String>) -> some View {
        VStack {
            HStack {
                TextField("", text: text, prompt: Text(title).foregroundColor(.neutral300))
                    .borderlessTextFieldStyle()
                    .foregroundColor(.neutral0)
                    .tint(.neutral0)
                    .font(.body16Menlo)
                    .submitLabel(.done)
                    .disableAutocorrection(true)
                    .textFieldStyle(TappableTextFieldStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                .foregroundColor(.blue600)
        )
    }

    var pair: some View {
        KeysignDiscoveryView(
            vault: vault,
            keysignPayload: nil,
            customMessagePayload: customMessagePayload,
            transferViewModel: viewModel,
            fastVaultPassword: nil,
            keysignView: $keysignView,
            shareSheetViewModel: shareSheetViewModel
        )
    }

    var buttonLabel: some View {
        return Button {
            viewModel.moveToNextView()
        } label: {
            FilledButton(title: "Sign")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(!buttonEnabled)
        .opacity(buttonEnabled ? 1 : 0.5)
    }

    var backButton: some View {
        return Button {
            viewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
                .offset(x: -8)
        }
        .opacity(viewModel.state == .done ? 0 : 1)
        .disabled(viewModel.state == .done)
    }

    var buttonEnabled: Bool {
        return !method.isEmpty && !message.isEmpty
    }

    var customMessagePayload: CustomMessagePayload? {
        return CustomMessagePayload(method: method, message: message)
    }
}
