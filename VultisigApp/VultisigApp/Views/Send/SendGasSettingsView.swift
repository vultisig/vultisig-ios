//
//  SendGasSettingsView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 28.08.2024.
//

import SwiftUI

struct SendGasSettingsView: View {

    @Environment(\.presentationMode) var presentationMode

    @Binding var gasLimit: String
    @Binding var baseFee: String
    @Binding var totalFee: String
    @Binding var selectedMode: FeeMode

    var totalFeeFiat: String {
        return "$3.4"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Background()
                view
            }
            .toolbar {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.backward")
                            .font(.body18MenloBold)
                            .foregroundColor(Color.neutral0)
                    }
                }
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    saveButton
                }
            }
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
    }

    var baseFeeRow: some View {
        VStack {
            title(text: "Current Base Fee (Gwei)")
            textField(title: "Base Fee", text: $baseFee)
        }
    }

    var gasLimitRow: some View {
        VStack {
            title(text: "Gas Limit")
            textField(title: "Gas Limit", text: $gasLimit)
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
            textField(title: "Total Fee", text: $totalFee, label: totalFeeFiat)
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
            if selectedMode == mode {
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

#Preview {
    SendGasSettingsView(gasLimit: .constant("21000"), baseFee: .constant("6.559000"), totalFee: .constant("11.25"), selectedMode: .constant(.normal))
}
