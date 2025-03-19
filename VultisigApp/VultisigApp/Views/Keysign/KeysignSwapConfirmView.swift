//
//  KeysignSwapConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.04.2024.
//

import SwiftUI

struct KeysignSwapConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        VStack {
            fields
            button
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
            }
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            getValueCell(for: "action", with: getAction())
            Separator()
            getValueCell(for: "provider", with: getProvider())
            Separator()
            getValueCell(for: "fromAsset", with: getFromAmount())
            Separator()
            getValueCell(for: "toAsset", with: getToAmount())
            if showApprove {
                Separator()
                getValueCell(for: "Allowance spender", with: getSpender())
                Separator()
                getValueCell(for: "Allowance amount", with: getAmount())
            }
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "sign")
        }
        .padding(20)
    }

    func getAction() -> String {
        guard viewModel.keysignPayload?.approvePayload == nil else {
            return NSLocalizedString("Approve and Swap", comment: "")
        }
        return NSLocalizedString("Swap", comment: "")
    }

    func getProvider() -> String {
        switch viewModel.keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .none:
            return .empty
        }
    }

    var showApprove: Bool {
        viewModel.keysignPayload?.approvePayload != nil
    }

    func getSpender() -> String {
        return viewModel.keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount() -> String {
        guard let fromCoin = viewModel.keysignPayload?.coin, let amount = viewModel.keysignPayload?.approvePayload?.amount else {
            return .empty
        }

        return "\(String(describing: fromCoin.decimal(for: amount)).formatCurrencyWithSeparators()) \(fromCoin.ticker)"
    }

    func getFromAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker) (\(payload.toCoin.chain.ticker))"
        }
    }

    func getValueCell(for title: String, with value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)

            Text(value)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

#Preview {
    KeysignSwapConfirmView(viewModel: JoinKeysignViewModel())
}
