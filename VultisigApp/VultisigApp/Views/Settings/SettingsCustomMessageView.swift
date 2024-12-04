//
//  SettingsCustomMessageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.12.2024.
//

import SwiftUI

struct SettingsCustomMessageView: View {

    @Environment(\.dismiss) var dismiss

    @StateObject var transferViewModel = FakeTransferViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State var keysignView: KeysignView?
    @State var method: String = .empty
    @State var message: String = .empty

    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle("Sign message")
    }

    var view: some View {
        ScrollView {
            VStack(spacing: 16) {
                textField(title: "Method", text: $method)
                textField(title: "Message", text: $message)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            button
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
                    .submitLabel(.next)
                    .disableAutocorrection(true)
                    .textFieldStyle(TappableTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .textContentType(.oneTimeCode)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                .foregroundColor(.blue600)
        )
        .padding(.horizontal, 16)
    }

    var button: some View {
        return NavigationLink {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: nil,
                customMessagePayload: customMessagePayload,
                transferViewModel: transferViewModel,
                fastVaultPassword: nil,
                keysignView: $keysignView,
                shareSheetViewModel: shareSheetViewModel
            )
        } label: {
            FilledButton(title: "Sign")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    var customMessagePayload: CustomMessagePayload? {
        return CustomMessagePayload(method: method, message: message)
    }
}
