//
//  DepositDetailView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import OSLog
import SwiftUI

enum DepositField: Int, Hashable {
    case toAddress
    case amount
    case amountInFiat
}

struct DepositDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var depositViewModel: DepositViewModel
    let group: GroupedChain
    
    @State var amount = ""
    @State var nativeTokenBalance = ""
    
    @FocusState private var focusedField: DepositField?
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                
                Button {
                    hideKeyboard()
                } label: {
                    Text(NSLocalizedString("done", comment: "Done"))
                }
            }
        }
        .alert(isPresented: $depositViewModel.showAlert) {
            alert
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(depositViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                coinSelector
                fromField
                toField
                amountField
            }
            .padding(.horizontal, 16)
        }
    }
    
    var coinSelector: some View {
        TokenSelectorDropdown(coins: .constant(group.coins), selected: $tx.coin)
    }
    
    var fromField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
            fromTextField
        }
    }
    
    var fromTextField: some View {
        Text(tx.fromAddress)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
            .lineLimit(1)
    }
    
    var toField: some View {
        VStack(spacing: 8) {
            getTitle(for: "to")
            AddressTextField(tx: tx, depositViewModel: depositViewModel)
                .focused($focusedField, equals: .toAddress)
                .onSubmit {
                    focusNextField($focusedField)
                }
        }
    }
    
    var amountField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount")
            
        }
    }
        
    var button: some View {
        Button {
            Task{
                await validateForm()
            }
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
    
    private func getTitle(for text: String) -> some View {
        Text(
            NSLocalizedString(text, comment: "")
                .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
        )
        .font(.body14MontserratMedium)
        .foregroundColor(.neutral0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func validateForm() async {
        if await depositViewModel.validateForm(tx: tx) {
            depositViewModel.moveToNextView()
        }
    }
}

#Preview {
    DepositDetailsView(
        tx: SendTransaction(),
        depositViewModel: DepositViewModel(),
        group: GroupedChain.example
    )
}
