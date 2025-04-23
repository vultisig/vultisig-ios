import Foundation
import OSLog
import SwiftUI

struct TransactionMemoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var transactionMemoViewModel: TransactionMemoViewModel
    @ObservedObject var vault: Vault

    @State private var selectedFunctionMemoType: TransactionMemoType
    @State private var selectedContractMemoType: TransactionMemoContractType
    @State private var showInvalidFormAlert = false
    
    @State var txMemoInstance: TransactionMemoInstance
    
    @StateObject var keyboardObserver = KeyboardObserver()

    init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel, vault: Vault
    ) {
        self.tx = tx
        self.transactionMemoViewModel = transactionMemoViewModel
        self.vault = vault
        let defaultCoin = tx.coin
        self._selectedFunctionMemoType = State(
            initialValue: TransactionMemoType.getDefault(for: defaultCoin))
        self._selectedContractMemoType = State(
            initialValue: TransactionMemoContractType.getDefault(
                for: defaultCoin))
        self._txMemoInstance = State(
            initialValue: TransactionMemoInstance.getDefault(for: defaultCoin, tx: tx, transactionMemoViewModel: transactionMemoViewModel, vault: vault))
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
                    txMemoInstance = .bond(TransactionMemoBond(tx: tx, transactionMemoViewModel: transactionMemoViewModel))
                case .unbond:
                    txMemoInstance = .unbond(TransactionMemoUnbond())
                case .bondMaya:

                    DispatchQueue.main.async {
                        MayachainService.shared.getDepositAssets {
                            assetsResponse in
                            let assets = assetsResponse.map {
                                IdentifiableString(value: $0)
                            }
                            DispatchQueue.main.async {
                                txMemoInstance = .bondMaya(
                                    TransactionMemoBondMayaChain(assets: assets)
                                )
                            }
                        }
                    }

                case .unbondMaya:

                    DispatchQueue.main.async {
                        MayachainService.shared.getDepositAssets {
                            assetsResponse in
                            let assets = assetsResponse.map {
                                IdentifiableString(value: $0)
                            }
                            DispatchQueue.main.async {
                                txMemoInstance = .unbondMaya(
                                    TransactionMemoUnbondMayaChain(
                                        assets: assets))
                            }
                        }
                    }

                case .leave:
                    txMemoInstance = .leave(TransactionMemoLeave())
                case .custom:
                    txMemoInstance = .custom(TransactionMemoCustom())
                case .vote:
                    txMemoInstance = .vote(TransactionMemoVote())
                case .stake:
                    txMemoInstance = .stake(TransactionMemoStake())
                case .unstake:
                    txMemoInstance = .unstake(TransactionMemoUnstake())
                case .addPool:
                    txMemoInstance = .addPool(
                        TransactionMemoAddLiquidityMaya()
                    )
                case .removePool:
                    txMemoInstance = .removePool(
                        TransactionMemoRemoveLiquidityMaya()
                    )
                    
                case .cosmosIBC:
                    txMemoInstance = .cosmosIBC(TransactionMemoCosmosIBC(tx: tx, transactionMemoViewModel: transactionMemoViewModel, vault: vault))
                case .merge:
                    txMemoInstance = .merge(TransactionMemoCosmosMerge(tx: tx, transactionMemoViewModel: transactionMemoViewModel, vault: vault))
                case .theSwitch:
                    txMemoInstance = .theSwitch(TransactionMemoCosmosSwitch(tx: tx, transactionMemoViewModel: transactionMemoViewModel, vault: vault))
                }
            }
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(
                NSLocalizedString(
                    transactionMemoViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var invalidFormAlert: Alert {
        Alert(
            title: Text("Form Invalid"),
            message: Text(
                "The form is not valid. Please fix the fields marked with a red star."
            ),
            dismissButton: .default(Text("OK"))
        )
    }

    var functionSelector: some View {
        TransactionMemoSelectorDropdown(
            items: .constant(TransactionMemoType.getCases(for: tx.coin)),
            selected: $selectedFunctionMemoType, coin: $tx.coin)
    }

    var contractSelector: some View {
        TransactionMemoContractSelectorDropDown(
            items: .constant(
                TransactionMemoContractType.getCases(for: tx.coin)),
            selected: $selectedContractMemoType, coin: tx.coin)
    }

    var button: some View {
        Button {
            Task {
                if txMemoInstance.isTheFormValid {
                    tx.amount = txMemoInstance.amount.description
                    tx.memo = txMemoInstance.description
                    tx.memoFunctionDictionary = txMemoInstance.toDictionary()
                    tx.transactionType = txMemoInstance.getTransactionType()
                    
                    if let toAddress = txMemoInstance.toAddress {
                        tx.toAddress = toAddress
                    }
                    
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
