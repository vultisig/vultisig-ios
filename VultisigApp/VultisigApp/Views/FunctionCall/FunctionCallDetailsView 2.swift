//
//  FunctionCallDetailsView 2.swift
//  VultisigApp
//
//  Created by dev on 5/5/2025.
//


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
    
    @State var txMemoInstance: FunctionCallInstance
    
    @StateObject var keyboardObserver = KeyboardObserver()

    init(
        tx: SendTransaction, transactionMemoViewModel: FunctionCallViewModel, vault: Vault
    ) {
        self.tx = tx
        self.functionCallViewModel = transactionMemoViewModel
        self.vault = vault
        let defaultCoin = tx.coin
        self._selectedFunctionMemoType = State(
            initialValue: FunctionCallType.getDefault(for: defaultCoin))
        self._selectedContractMemoType = State(
            initialValue: FunctionCallContractType.getDefault(
                for: defaultCoin))
        self._txMemoInstance = State(
            initialValue: FunctionCallInstance.getDefault(for: defaultCoin, tx: tx, transactionMemoViewModel: transactionMemoViewModel, vault: vault))
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
                    txMemoInstance = .bond(FunctionCallBond(tx: tx, transactionMemoViewModel: functionCallViewModel))
                case .unbond:
                    txMemoInstance = .unbond(FunctionCallUnbond())
                case .bondMaya:

                    DispatchQueue.main.async {
                        MayachainService.shared.getDepositAssets {
                            assetsResponse in
                            let assets = assetsResponse.map {
                                IdentifiableString(value: $0)
                            }
                            DispatchQueue.main.async {
                                txMemoInstance = .bondMaya(
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
                                txMemoInstance = .unbondMaya(
                                    FunctionCallUnbondMayaChain(
                                        assets: assets))
                            }
                        }
                    }

                case .leave:
                    txMemoInstance = .leave(FunctionCallLeave())
                case .custom:
                    txMemoInstance = .custom(FunctionCallCustom())
                case .vote:
                    txMemoInstance = .vote(FunctionCallVote())
                case .stake:
                    txMemoInstance = .stake(FunctionCallStake())
                case .unstake:
                    txMemoInstance = .unstake(FunctionCallUnstake())
                case .addPool:
                    txMemoInstance = .addPool(
                        FunctionCallAddLiquidityMaya()
                    )
                case .removePool:
                    txMemoInstance = .removePool(
                        FunctionCallRemoveLiquidityMaya()
                    )
                    
                case .cosmosIBC:
                    txMemoInstance = .cosmosIBC(FunctionCallCosmosIBC(tx: tx, transactionMemoViewModel: functionCallViewModel, vault: vault))
                case .merge:
                    txMemoInstance = .merge(FunctionCallCosmosMerge(tx: tx, transactionMemoViewModel: functionCallViewModel, vault: vault))
                case .theSwitch:
                    txMemoInstance = .theSwitch(FunctionCallCosmosSwitch(tx: tx, transactionMemoViewModel: functionCallViewModel, vault: vault))
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
        TransactionMemoSelectorDropdown(
            items: .constant(FunctionCallType.getCases(for: tx.coin)),
            selected: $selectedFunctionMemoType, coin: $tx.coin)
    }

    var contractSelector: some View {
        TransactionMemoContractSelectorDropDown(
            items: .constant(
                FunctionCallContractType.getCases(for: tx.coin)),
            selected: $selectedContractMemoType, coin: tx.coin)
    }

    var button: some View {
        Button {
            Task {
                if txMemoInstance.isTheFormValid {
                    tx.amount = txMemoInstance.amount.formatDecimalToLocale()
                    tx.memo = txMemoInstance.description
                    tx.memoFunctionDictionary = txMemoInstance.toDictionary()
                    tx.transactionType = txMemoInstance.getTransactionType()
                    
                    if let toAddress = txMemoInstance.toAddress {
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