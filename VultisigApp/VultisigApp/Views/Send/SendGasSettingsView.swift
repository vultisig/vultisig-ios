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
            textField(title: "Base Fee", text: $viewModel.baseFee)
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
            textField(title: "Total Fee", text: $viewModel.totalFee, label: viewModel.totalFeeFiat)
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

    func textField(title: String, text: Binding<String>, label: String? = nil) -> some View {
        VStack {
            HStack {
                TextField(title, text: text)
                    .foregroundColor(.white)
                    .font(.body16Menlo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)

                if let label {
                    Text(label)
                        .foregroundColor(.neutral300)
                        .font(.body16Menlo)
                }
            }
        }
        .background(
            RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                .foregroundColor(.blue600)
        )
        .padding(.horizontal, 16)
    }

    func modeTab(mode: FeeMode) -> some View {
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

    var backButton: some View {
        Button(action: {
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "chevron.backward")
                .font(.body18MenloBold)
                .foregroundColor(Color.neutral0)
        }
    }

    var saveButton: some View {
        Button("Save", action: { presentationMode.wrappedValue.dismiss() })
    }
}

#Preview {
    struct Output: SendGasSettingsOutput {
        func didSetFeeSettings(gasLimit: BigInt, mode: FeeMode) { }
    }
    let viewModel = SendGasSettingsViewModel(gasLimit: "21000", baseFee: "6.559000", totalFee: "11.25", selectedMode: .normal)
    return SendGasSettingsView(viewModel: viewModel, output: Output())
}