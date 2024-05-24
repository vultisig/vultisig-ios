import Foundation
import OSLog
import SwiftUI
import Foundation
import OSLog
import SwiftUI

struct TransactionMemoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var transactionMemoViewModel: TransactionMemoViewModel
    
    @State var amount = ""
    @State var nativeTokenBalance = ""
    
    @State private var selectedContractMemoType: TransactionMemoContractType = .thorChainMessageDeposit
    
    @State private var selectedFunctionMemoType: TransactionMemoType = .bond
    @State private var txMemoInstance: TransactionMemoInstance = .bond(TransactionMemoBond())
    
    @State private var selectedFunctionMemoExpertType: TransactionMemoExpertType = .bond
    @State private var txMemoExpertInstance: TransactionMemoExpertInstance = .bond(TransactionMemoBond())
    
    @State private var isExpertMode = false
    
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
        .alert(isPresented: $transactionMemoViewModel.showAlert) {
            alert
        }
        .onChange(of: selectedFunctionMemoType) {
            switch selectedFunctionMemoType {
            case .bond:
                txMemoInstance = .bond(TransactionMemoBond())
            case .unbond:
                txMemoInstance = .unbond(TransactionMemoUnbond())
            case .leave:
                txMemoInstance = .leave(TransactionMemoLeave())
            }
        }
        .onChange(of: selectedFunctionMemoExpertType) {
            switch selectedFunctionMemoExpertType {
            case .bond:
                txMemoExpertInstance = .bond(TransactionMemoBond())
            case .unbond:
                txMemoExpertInstance = .unbond(TransactionMemoUnbond())
            case .leave:
                txMemoExpertInstance = .leave(TransactionMemoLeave())
            case .swap:
                txMemoExpertInstance = .swap(TransactionMemoSwap())
            case .depositSavers:
                txMemoExpertInstance = .depositSavers(TransactionMemoDepositSavers())
            case .withdrawSavers:
                txMemoExpertInstance = .withdrawSavers(TransactionMemoWithdrawSavers())
            case .openLoan:
                txMemoExpertInstance = .openLoan(TransactionMemoOpenLoan())
            case .repayLoan:
                txMemoExpertInstance = .repayLoan(TransactionMemoRepayLoan())
            case .addLiquidity:
                txMemoExpertInstance = .addLiquidity(TransactionMemoAddLiquidity())
            case .withdrawLiquidity:
                txMemoExpertInstance = .withdrawLiquidity(TransactionMemoWithdrawLiquidity())
            case .addTradeAccount:
                txMemoExpertInstance = .addTradeAccount(TransactionMemoAddTradeAccount())
            case .withdrawTradeAccount:
                txMemoExpertInstance = .withdrawTradeAccount(TransactionMemoWithdrawTradeAccount())
            case .donateReserve:
                txMemoExpertInstance = .donateReserve(TransactionMemoDonateReserve())
            case .migrate:
                txMemoExpertInstance = .migrate(TransactionMemoMigrate())
            }
        }
        .onChange(of: selectedContractMemoType) {
            isExpertMode = selectedContractMemoType == TransactionMemoContractType.thorChainMessageDepositExpert
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
            message: Text(NSLocalizedString(transactionMemoViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                contractSelector
                functionSelector
                if isExpertMode {
                    txMemoExpertInstance.view
                } else {
                    txMemoInstance.view
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    var functionSelector: some View {
        Group {
            if isExpertMode {
                GenericEnumSelectorDropdown(items: .constant(Array(TransactionMemoExpertType.allCases)), selected: $selectedFunctionMemoExpertType)
            } else {
                GenericEnumSelectorDropdown(items: .constant(Array(TransactionMemoType.allCases)), selected: $selectedFunctionMemoType)
            }
        }
    }
    
    var contractSelector: some View {
        TransactionMemoContractSelectorDropDown(items: .constant(TransactionMemoContractType.allCases), selected: $selectedContractMemoType)
    }
    
    var fromField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
        }
    }
    
    var button: some View {
        Button {
            Task {
                if isExpertMode {
                    tx.amount = "1"
                    tx.memo = txMemoExpertInstance.description
                    tx.memoFunctionDictionary = txMemoExpertInstance.toDictionary()
                    print(tx.memo)
                } else {
                    tx.amount = txMemoInstance.amount.description
                    tx.memo = txMemoInstance.description
                    tx.memoFunctionDictionary = txMemoInstance.toDictionary()
                    print(tx.memo)
                }
                transactionMemoViewModel.moveToNextView()
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
