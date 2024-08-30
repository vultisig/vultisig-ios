//
//  SendGasSettingsView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 28.08.2024.
//

import SwiftUI
import BigInt

protocol SendGasSettingsOutput {
    func didSetFeeSettings(gasLimit: BigInt, mode: FeeMode)
}

struct SendGasSettingsView: View {

    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var viewModel: SendGasSettingsViewModel

    let output: SendGasSettingsOutput

    var body: some View {
        NavigationView {
            ZStack {
                Background()
                view
            }
            .navigationBarItems(leading: backButton, trailing: saveButton)
            .navigationTitle("Advanced")
            .navigationBarTitleTextColor(.neutral0)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            try? await viewModel.fetch(chain: viewModel.chain)
        }
    }

    var view: some View {
        VStack(spacing: 16) {
            baseFeeRow
            gasLimitRow
            feeModeRow
            totalFeeRow

            Spacer()
        }
        .padding(.top, 16)
    }

    var baseFeeRow: some View {
        VStack {
            title(text: "Current Base Fee (Gwei)")
            textField(title: "Base Fee", text: $viewModel.baseFee, disabled: true)
        }
    }

    var gasLimitRow: some View {
        VStack {
            title(text: "Gas Limit")
            textField(title: "Gas Limit", text: $viewModel.gasLimit)
        }
    }

    var feeModeRow: some View {
        VStack {
            title(text: "Priority")

            HStack {
                ForEach(FeeMode.allCases, id: \.title) { mode in
                    modeTab(mode: mode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    var totalFeeRow: some View {
        VStack {
            title(text: "Total Fee (Gwei)")
            textField(title: "Total Fee", text: .constant(viewModel.totalFee), label: viewModel.totalFeeFiat)
        }
    }


    func title(text: String) -> some View {
        HStack {
            Text(text)
                .font(.body14Montserrat)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    func textField(title: String, text: Binding<String>, label: String? = nil, disabled: Bool = false) -> some View {
        VStack {
            HStack {
                TextField("", text: text, prompt: Text(title).foregroundColor(.neutral300))
                    .borderlessTextFieldStyle()
                    .foregroundColor(disabled ? .neutral300 : .neutral0)
                    .tint(.neutral0)
                    .font(.body16Menlo)
                    .submitLabel(.next)
                    .disableAutocorrection(true)
                    .textFieldStyle(TappableTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .textContentType(.oneTimeCode)
                    .disabled(disabled)

                if let label {
                    Text(label)
                        .foregroundColor(.neutral300)
                        .font(.body16Menlo)
                }
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

    func modeTab(mode: FeeMode) -> some View {
        Button {
            viewModel.selectedMode = mode
        } label: {
            ZStack {
                if viewModel.selectedMode == mode {
                    Text(mode.title)
                        .font(.body16MontserratBold)
                        .foregroundColor(.blue800)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(LinearGradient.primaryGradientHorizontal)
                        .cornerRadius(30)
                } else {
                    OutlineButton(title: mode.title, gradient: .primaryGradientHorizontal)
                }
            }
        }
    }

    var backButton: some View {
        Button(action: {
            presentationMode.wrappedValue.dismiss()
        }) {
            Image("x")
                .font(.body18MenloBold)
                .foregroundColor(Color.neutral0)
        }
    }

    var saveButton: some View {
        Button("Save", action: {
            save()
            presentationMode.wrappedValue.dismiss()
        })
    }

    func save() {
        guard let gasLimit = BigInt(viewModel.gasLimit, radix: 10) else {
            return
        }
        output.didSetFeeSettings(gasLimit: gasLimit, mode: viewModel.selectedMode)
    }
}

#Preview {
    struct Output: SendGasSettingsOutput {
        func didSetFeeSettings(gasLimit: BigInt, mode: FeeMode) { }
    }
    let viewModel = SendGasSettingsViewModel(coin: .example, gasLimit: "21000", baseFee: "6.559000", selectedMode: .normal)
    return SendGasSettingsView(viewModel: viewModel, output: Output())
}
