import Foundation
import OSLog
import SwiftUI

struct TransactionMemoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var transactionMemoViewModel: TransactionMemoViewModel
    
    @State var amount = ""
    @State var nativeTokenBalance = ""
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
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
#if os(iOS)
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
#endif
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
                
            }
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
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
    
    var fromField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
        }
    }
    
    var button: some View {
        Button {
            Task {
                if txMemoInstance.isTheFormValid {
                    tx.amount = txMemoInstance.amount.description
                    tx.memo = txMemoInstance.description
                    tx.memoFunctionDictionary = txMemoInstance.toDictionary()
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
    
    private func getTitle(for text: String) -> some View {
        Text(
            NSLocalizedString(text, comment: .empty)
                .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
        )
        .font(.body14MontserratMedium)
        .foregroundColor(.neutral0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: .empty)
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
}

#Preview {
    TransactionMemoDetailsView(
        tx: SendTransaction(),
        transactionMemoViewModel: TransactionMemoViewModel()
    )
}
