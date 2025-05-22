import Foundation
import OSLog
import SwiftUI

struct FunctionCallDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var functionCallViewModel: FunctionCallViewModel
    @ObservedObject var vault: Vault

    @State private var selectedFunctionMemoType: FunctionCallType
    @State private var selectedContractMemoType: FunctionCallContractType
    @State private var showInvalidFormAlert = false
    
    @State var fnCallInstance: FunctionCallInstance
    
    @StateObject var keyboardObserver = KeyboardObserver()

    init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault
    ) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
        let defaultCoin = tx.coin
        self._selectedFunctionMemoType = State(
            initialValue: FunctionCallType.getDefault(for: defaultCoin))
        self._selectedContractMemoType = State(
            initialValue: FunctionCallContractType.getDefault(
                for: defaultCoin))
        self._fnCallInstance = State(
            initialValue: FunctionCallInstance.getDefault(for: defaultCoin, tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
    }

    var body: some View {
        content
            .alert(isPresented: $functionCallViewModel.showAlert) {
                alert
            }
            .alert(isPresented: $showInvalidFormAlert) {
                invalidFormAlert
            }
            .onChange(of: selectedFunctionMemoType) {
                switch selectedFunctionMemoType {
                case .bond:
                    fnCallInstance = .bond(FunctionCallBond(tx: tx, functionCallViewModel: functionCallViewModel))
                case .unbond:
                    
                    DispatchQueue.main.async {
                        ThorchainService.shared.fetchNodeBonds(address: tx.coin.address) {
                            bonds in
                            
                            DispatchQueue.main.async {
                                fnCallInstance = .unbond(FunctionCallUnbond(bonds: bonds))
                            }
                        }
                    }
                    
                case .bondMaya:

                    DispatchQueue.main.async {
                        MayachainService.shared.getDepositAssets {
                            assetsResponse in
                            let assets = assetsResponse.map {
                                IdentifiableString(value: $0)
                            }
                            DispatchQueue.main.async {
                                fnCallInstance = .bondMaya(
                                    FunctionCallBondMayaChain(assets: assets)
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
                                fnCallInstance = .unbondMaya(
                                    FunctionCallUnbondMayaChain(
                                        assets: assets))
                            }
                        }
                    }

                case .leave:
                    fnCallInstance = .leave(FunctionCallLeave())
                case .custom:
                    fnCallInstance = .custom(FunctionCallCustom())
                case .vote:
                    fnCallInstance = .vote(FunctionCallVote())
                case .stake:
                    fnCallInstance = .stake(FunctionCallStake())
                case .stakeTcy:
                    fnCallInstance = .stakeTcy(FunctionCallStakeTCY(tx: tx, functionCallViewModel: functionCallViewModel))
                case .unstakeTcy:
                    
                    DispatchQueue.main.async {
                        ThorchainService.shared.fetchTcyStakedAmount(address: tx.coin.address) {
                            stakedAmount in
                            
                            DispatchQueue.main.async {
                                fnCallInstance = .unstakeTcy(FunctionCallUnstakeTCY(tx: tx, functionCallViewModel: functionCallViewModel, stakedAmount: stakedAmount))
                            }
                        }
                    }
                    
                case .unstake:
                    fnCallInstance = .unstake(FunctionCallUnstake())
                case .addPool:
                    fnCallInstance = .addPool(
                        FunctionCallAddLiquidityMaya()
                    )
                case .removePool:
                    fnCallInstance = .removePool(
                        FunctionCallRemoveLiquidityMaya()
                    )
                    
                case .cosmosIBC:
                    fnCallInstance = .cosmosIBC(FunctionCallCosmosIBC(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .merge:
                    fnCallInstance = .merge(FunctionCallCosmosMerge(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .theSwitch:
                    fnCallInstance = .theSwitch(FunctionCallCosmosSwitch(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                }
            }
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(
                NSLocalizedString(
                    functionCallViewModel.errorMessage, comment: "")),
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
        FunctionCallSelectorDropdown(
            items: .constant(FunctionCallType.getCases(for: tx.coin)),
            selected: $selectedFunctionMemoType, coin: $tx.coin)
    }

    var contractSelector: some View {
        FunctionCallContractSelectorDropDown(
            items: .constant(
                FunctionCallContractType.getCases(for: tx.coin)),
            selected: $selectedContractMemoType, coin: tx.coin)
    }

    var button: some View {
        Button {
            Task {
                if fnCallInstance.isTheFormValid {
                    tx.amount = fnCallInstance.amount.formatDecimalToLocale()
                    tx.memo = fnCallInstance.description
                    tx.memoFunctionDictionary = fnCallInstance.toDictionary()
                    tx.transactionType = fnCallInstance.getTransactionType()
                    
                    if let toAddress = fnCallInstance.toAddress {
                        tx.toAddress = toAddress
                    }
                    
                    functionCallViewModel.moveToNextView()
                    
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
