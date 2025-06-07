//
//  SendGasSettingsView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 28.08.2024.
//

import SwiftUI
import BigInt

protocol SendGasSettingsOutput {
    func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?)
}

struct SendGasSettingsView: View {

    @Environment(\.presentationMode) var presentationMode

    @StateObject var viewModel: SendGasSettingsViewModel

    let output: SendGasSettingsOutput

    var body: some View {
        content
            .task {
                fetch()
            }
            .onChange(of: viewModel.selectedMode) { _, _ in
                fetch()
            }
    }

    var view: some View {
        VStack(spacing: 16) {
            feeModeRow

            switch viewModel.chain.chainType {
            case .UTXO:
                networkRateRow
            case .EVM:
                baseFeeRow
                gasLimitRow
                totalFeeRow
            default:
                EmptyView()
            }

            Spacer()
        }
        .padding(.top, 16)
    }

    var networkRateRow: some View {
        VStack {
            title(text: "Network rate (sats/vbyte)")
            textField(title: "Network rate", text: $viewModel.byteFee)
        }
    }

    var baseFeeRow: some View {
        VStack {
            title(text: "Current Base Fee (Gwei)")
            label(title: "Base Fee", text: viewModel.baseFee)
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
            textField(title: "Total Fee", text: .constant(viewModel.totalFee), label: viewModel.totalFeeFiat,disabled: true)
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

    func label(title: String, text: String) -> some View {
        VStack {
            HStack {
                Text(text.isEmpty ? title : text)
                    .font(.body16Menlo)
                    .foregroundColor(.neutral300)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)

                Spacer()
            }

        }
        .background(
            RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                .foregroundColor(.blue600)
        )
        .frame(maxWidth: .infinity)
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
                        .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
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

    func fetch() {
        Task {
            try await viewModel.fetch(chain: viewModel.chain)
        }
    }

    func save() {
        let gasLimit = BigInt(viewModel.gasLimit, radix: 10)
        let byteFee = BigInt(viewModel.byteFee, radix: 10)

        output.didSetFeeSettings(
            chain: viewModel.chain,
            mode: viewModel.selectedMode,
            gasLimit: gasLimit,
            byteFee: byteFee
        )
    }
}

#Preview {
    struct Output: SendGasSettingsOutput {
        func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?) { }
    }
    let viewModel = SendGasSettingsViewModel(coin: .example, vault: .example, gasLimit: "21000", byteFee: "2", baseFee: "6.559000", selectedMode: .default)
    return SendGasSettingsView(viewModel: viewModel, output: Output())
}
