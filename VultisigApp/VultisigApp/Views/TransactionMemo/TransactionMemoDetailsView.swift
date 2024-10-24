import Foundation
import OSLog
import SwiftUI

struct TransactionMemoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var transactionMemoViewModel: TransactionMemoViewModel
    
    @State private var selectedFunctionMemoType: TransactionMemoType
    @State private var selectedContractMemoType: TransactionMemoContractType
    @State private var txMemoInstance: TransactionMemoInstance
    @State private var showInvalidFormAlert = false
    
    init(tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel) {
        self.tx = tx
        self.transactionMemoViewModel = transactionMemoViewModel
        let defaultCoin = tx.coin
        self._selectedFunctionMemoType = State(initialValue: TransactionMemoType.getDefault(for: defaultCoin))
        self._selectedContractMemoType = State(initialValue: TransactionMemoContractType.getDefault(for: defaultCoin))
        self._txMemoInstance = State(initialValue: TransactionMemoInstance.getDefault(for: defaultCoin))
    }
    
    var body: some View {
        content
            .alert(isPresented: $transactionMemoViewModel.showAlert) {
                alert
            }
            .alert(isPresented: $showInvalidFormAlert) {
                invalidFormAlert
            }
            .onChange(of: selectedFunctionMemoType) {
                switch selectedFunctionMemoType {
                case .bond:
                    txMemoInstance = .bond(TransactionMemoBond())
                case .unbond:
                    txMemoInstance = .unbond(TransactionMemoUnbond())
                case .leave:
                    txMemoInstance = .leave(TransactionMemoLeave())
                case .custom:
                    txMemoInstance = .custom(TransactionMemoCustom())
                case .vote:
                    txMemoInstance = .vote(TransactionMemoVote())
                case .addPool:
                    txMemoInstance = .addPool(TransactionMemoAddPool())
                case .withdrawPool:
                    txMemoInstance = .withdrawPool(TransactionMemoWithdrawPool())
                }
            }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(transactionMemoViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var invalidFormAlert: Alert {
        Alert(
            title: Text("Form Invalid"),
            message: Text("The form is not valid. Please fix the fields marked with a red star."),
            dismissButton: .default(Text("OK"))
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                contractSelector
                functionSelector
                txMemoInstance.view
            }
            .padding(.horizontal, 16)
        }
    }
    
    var functionSelector: some View {
        TransactionMemoSelectorDropdown(items: .constant(TransactionMemoType.getCases(for: tx.coin)), selected: $selectedFunctionMemoType)
    }
    
    var contractSelector: some View {
        TransactionMemoContractSelectorDropDown(items: .constant(TransactionMemoContractType.getCases(for: tx.coin)), selected: $selectedContractMemoType, coin: tx.coin)
    }
    
    var button: some View {
        Button {
            Task {
                if txMemoInstance.isTheFormValid {
                    tx.amount =   txMemoInstance.amount.description.formatToDecimal(digits: tx.coin.decimals)
                    tx.memo = txMemoInstance.description
                    tx.memoFunctionDictionary = txMemoInstance.toDictionary()
                    tx.transactionType = txMemoInstance.getTransactionType()
                    transactionMemoViewModel.moveToNextView()
                } else {
                    showInvalidFormAlert = true
                }
            }
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
}

#Preview {
    TransactionMemoDetailsView(
        tx: SendTransaction(),
        transactionMemoViewModel: TransactionMemoViewModel()
    )
}
