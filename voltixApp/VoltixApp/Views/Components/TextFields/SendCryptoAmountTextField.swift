//
//  SendCryptoAmountTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoAmountTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var utxoBtc: BitcoinUnspentOutputsService
    @ObservedObject var utxoLtc: LitecoinUnspentOutputsService
    @ObservedObject var eth: EthplorerAPIService
    @ObservedObject var thor: ThorchainService
    @ObservedObject var sol: SolanaService
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    var showButton = true
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if tx.amount.isEmpty {
                Text(NSLocalizedString("enterAmount", comment: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterAmount", comment: "").capitalized, text: Binding<String>(
                    get: { self.tx.amount },
                    set: { newValue in
                        self.tx.amount = newValue
                        DebounceHelper.shared.debounce {
                            sendCryptoViewModel.convertToUSD(newValue: newValue, tx: tx, eth: eth)
                        }
                    }
                ))
                .submitLabel(.next)
                
                if showButton {
                    maxButton
                }
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var maxButton: some View {
        Button {
            sendCryptoViewModel.setMaxValues(
                tx: tx,
                utxoBtc: utxoBtc,
                utxoLtc: utxoLtc,
                eth: eth,
                thor: thor,
                sol: sol
            )
        } label: {
            Text(NSLocalizedString("max", comment: "").uppercased())
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
}

#Preview {
    SendCryptoAmountTextField(
        tx: SendTransaction(),
        utxoBtc: BitcoinUnspentOutputsService(),
        utxoLtc: LitecoinUnspentOutputsService(),
        eth: EthplorerAPIService(),
        thor: ThorchainService.shared,
        sol: SolanaService.shared,
        sendCryptoViewModel: SendCryptoViewModel()
    )
}
