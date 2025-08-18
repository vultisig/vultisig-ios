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
    let defaultCoin: Coin
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    init(
        tx: SendTransaction,
        functionCallViewModel: FunctionCallViewModel,
        vault: Vault,
        defaultCoin: Coin?
    ) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
        let defaultCoin = defaultCoin ?? tx.coin
        self.defaultCoin = defaultCoin
        let dict = tx.memoFunctionDictionary
        if let nodeAddress = dict.get("nodeAddress"), !nodeAddress.isEmpty {
            if let actionStr = dict.get("action") {
                let functionType: FunctionCallType
                
                switch actionStr.lowercased() {
                case "bond":
                    functionType = .bond
                    self._selectedFunctionMemoType = State(initialValue: functionType)
                    self._selectedContractMemoType = State(initialValue: FunctionCallContractType.getDefault(for: defaultCoin))
                    
                    let bondInstance = FunctionCallBond(tx: tx, functionCallViewModel: functionCallViewModel)
                    bondInstance.nodeAddress = nodeAddress
                    bondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    if let feeStr = dict.get("fee"), let feeInt = Int64(feeStr) {
                        bondInstance.fee = feeInt
                        bondInstance.feeValid = true
                    }
                    self._fnCallInstance = State(initialValue: .bond(bondInstance))
                    return
                    
                case "unbond":
                    functionType = .unbond
                    self._selectedFunctionMemoType = State(initialValue: functionType)
                    self._selectedContractMemoType = State(initialValue: FunctionCallContractType.getDefault(for: defaultCoin))
                    
                    let unbondInstance = FunctionCallUnbond()
                    unbondInstance.nodeAddress = nodeAddress
                    unbondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    if let amountStr = dict.get("amount"), let amountDecimal = Decimal(string: amountStr) {
                        unbondInstance.amount = amountDecimal
                        unbondInstance.amountValid = true
                    }
                    self._fnCallInstance = State(initialValue: .unbond(unbondInstance))
                    return
                default:
                    break
                }
            }
        }
        self._selectedFunctionMemoType = State(
            initialValue: FunctionCallType.getDefault(for: defaultCoin))
        self._selectedContractMemoType = State(
            initialValue: FunctionCallContractType.getDefault(
                for: defaultCoin))
        self._fnCallInstance = State(
            initialValue: FunctionCallInstance.getDefault(for: defaultCoin, tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
    }
    
    private static func validateNodeAddress(_ address: String) -> Bool {
        return AddressService.validateAddress(address: address, chain: .thorChain) ||
        AddressService.validateAddress(address: address, chain: .mayaChain) ||
        AddressService.validateAddress(address: address, chain: .ton)
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
                let currentNodeAddress = extractNodeAddress(from: fnCallInstance)
                switch selectedFunctionMemoType {
                case .bond:
                    let bondInstance = FunctionCallBond(tx: tx, functionCallViewModel: functionCallViewModel)
                    
                    if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                        bondInstance.nodeAddress = nodeAddress
                        bondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    }
                    fnCallInstance = .bond(bondInstance)
                case .unbond:
                    let unbondInstance = FunctionCallUnbond()
                    
                    if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                        unbondInstance.nodeAddress = nodeAddress
                        unbondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    }
                    
                    fnCallInstance = .unbond(unbondInstance)
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
                    let leaveInstance = FunctionCallLeave()
                    
                    if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                        leaveInstance.nodeAddress = nodeAddress
                        leaveInstance.addressFields["nodeAddress"] = nodeAddress
                        
                        leaveInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    }
                    
                    fnCallInstance = .leave(leaveInstance)
                case .custom:
                    fnCallInstance = .custom(FunctionCallCustom())
                case .vote:
                    fnCallInstance = .vote(FunctionCallVote())
                case .stake:
                    fnCallInstance = .stake(FunctionCallStake())
                case .stakeTcy:
                    fnCallInstance = .stakeTcy(FunctionCallStakeTCY(tx: tx, vault: vault, functionCallViewModel: functionCallViewModel))
                case .unstakeTcy:
                    
                    DispatchQueue.main.async {
                        ThorchainService.shared.fetchTcyStakedAmount(address: tx.coin.address) {
                            stakedAmount in
                            
                            DispatchQueue.main.async {
                                fnCallInstance = .unstakeTcy(FunctionCallUnstakeTCY(tx: tx, vault: vault, functionCallViewModel: functionCallViewModel, stakedAmount: stakedAmount))
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
                case .unmerge:
                    fnCallInstance = .unmerge(FunctionCallCosmosUnmerge(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .theSwitch:
                    fnCallInstance = .theSwitch(FunctionCallCosmosSwitch(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .mintYRune:
                    fnCallInstance = .mintYRune(FunctionCallCosmosYVault(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault, action: .deposit, functionType: .mintYRune))
                case .mintYTCY:
                    fnCallInstance = .mintYTCY(FunctionCallCosmosYVault(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault, action: .deposit, functionType: .mintYTCY))
                case .redeemRune:
                    fnCallInstance = .redeemRune(FunctionCallCosmosYVault(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault, action: .withdraw(slippage: YVaultConstants.slippageOptions.first!), functionType: .redeemRune))
                case .redeemTCY:
                    fnCallInstance = .redeemTCY(FunctionCallCosmosYVault(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault, action: .withdraw(slippage: YVaultConstants.slippageOptions.first!), functionType: .redeemTCY))
                case .addThorLP:
                    fnCallInstance = .addThorLP(FunctionCallAddThorLP(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .removeThorLP:
                    fnCallInstance = .removeThorLP(FunctionCallRemoveThorLP(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
                case .stakeRuji:
                    functionCallViewModel.setRujiToken(to: tx, vault: vault)
                    fnCallInstance = .stakeRuji(FunctionCallStakeRuji(tx: tx, vault: vault, functionCallViewModel: functionCallViewModel))
                case .unstakeRuji:
                    functionCallViewModel.setRujiToken(to: tx, vault: vault)
                    fnCallInstance = .unstakeRuji(FunctionCallUnstakeRuji(tx: tx, functionCallViewModel: functionCallViewModel))
                case .withdrawRujiRewards:
                    functionCallViewModel.setRujiToken(to: tx, vault: vault)
                    fnCallInstance = .withdrawRujiRewards(FunctionCallWithdrawRujiRewards(tx: tx, functionCallViewModel: functionCallViewModel))
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
    
    private func extractNodeAddress(from instance: FunctionCallInstance) -> String? {
        switch instance {
        case .bond(let bond):
            return bond.nodeAddress
        case .unbond(let unbond):
            return unbond.nodeAddress
        case .leave(let leave):
            return leave.nodeAddress
        default:
            return nil
        }
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
        PrimaryButton(title: "continue") {
            Task {
                if fnCallInstance.isTheFormValid {
                    tx.amount = fnCallInstance.amount.formatToDecimal(digits: tx.coin.decimals)
                    tx.memo = fnCallInstance.description
                    tx.memoFunctionDictionary = fnCallInstance.toDictionary()
                    tx.transactionType = fnCallInstance.getTransactionType()
                    tx.wasmContractPayload = fnCallInstance.wasmContractPayload
                    
                    if let toAddress = fnCallInstance.toAddress {
                        tx.toAddress = toAddress
                    }
                    
                    functionCallViewModel.moveToNextView()
                    
                } else {
                    showInvalidFormAlert = true
                }
            }
        }
        .padding(40)
    }
}
