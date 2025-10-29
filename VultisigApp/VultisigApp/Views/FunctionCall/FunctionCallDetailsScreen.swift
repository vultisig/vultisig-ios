import Foundation
import OSLog
import SwiftUI

struct FunctionCallDetailsScreen: View {
    @ObservedObject var tx: SendTransaction
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @ObservedObject var vault: Vault
    
    @State private var selectedFunctionMemoType: FunctionCallType = .custom
    @State private var selectedContractMemoType: FunctionCallContractType = .thorChainMessageDeposit
    @State private var showInvalidFormAlert = false
    @State private var navigateToVerify = false
    @State private var hasCompletedInitialSetup = false
    
    @State var fnCallInstance: FunctionCallInstance?
    let defaultCoin: Coin
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    init(
        vault: Vault,
        tx: SendTransaction,
        defaultCoin: Coin?
    ) {
        self.vault = vault
        self.defaultCoin = defaultCoin ?? tx.coin
        self.tx = tx
    }
    
    private static func validateNodeAddress(_ address: String) -> Bool {
        return AddressService.validateAddress(address: address, chain: .thorChain) ||
        AddressService.validateAddress(address: address, chain: .mayaChain) ||
        AddressService.validateAddress(address: address, chain: .ton)
    }
    
    var body: some View {
        Screen(title: "function".localized) {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        contractSelector
                        functionSelector
                        if let fnView = fnCallInstance?.view {
                            fnView
                        }
                    }
                }
                button
            }
        }
        .navigationDestination(isPresented: $navigateToVerify) {
            FunctionCallRouteBuilder().buildVerifyScreen(tx: tx, vault: vault)
        }
        .alert(isPresented: $functionCallViewModel.showAlert) {
            alert
        }
        .alert(isPresented: $showInvalidFormAlert) {
            invalidFormAlert
        }
        .onLoad {
            setData()
            Task {
                await loadGasInfo()
            }
        }
        .onChange(of: tx.coin) {
            Task {
                await loadGasInfo()
            }
        }
        .onChange(of: selectedFunctionMemoType) {
            guard hasCompletedInitialSetup else { return }
            guard let fnInstance = fnCallInstance else { return }
            let currentNodeAddress = extractNodeAddress(from: fnInstance)
            switch selectedFunctionMemoType {
            case .bond:
                ensureRuneCoin()
                let bondInstance = FunctionCallBond(tx: tx, vault: vault)
                
                if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                    bondInstance.nodeAddress = nodeAddress
                    bondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                }
                fnCallInstance = .bond(bondInstance)
            case .unbond:
                // Ensure RUNE token is selected for UNBOND operations on THORChain
                ensureRuneCoin()
                let unbondInstance = FunctionCallUnbond(tx: tx, vault: vault)
                
                if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                    unbondInstance.nodeAddress = nodeAddress
                    unbondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                }
                
                fnCallInstance = .unbond(unbondInstance)
                
            case .rebond:
                // Ensure RUNE token is selected for REBOND operations on THORChain
                ensureRuneCoin()
                let rebondInstance = FunctionCallReBond(tx: tx, vault: vault)
                
                if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                    rebondInstance.nodeAddress = nodeAddress
                    rebondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                }
                
                fnCallInstance = .rebond(rebondInstance)
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
                // Ensure RUNE token is selected for LEAVE operations on THORChain
                ensureRuneCoin()
                let leaveInstance = FunctionCallLeave(tx: tx, vault: vault)
                
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
                fnCallInstance = .stake(FunctionCallStake(tx: tx))
            case .stakeTcy:
                // Ensure TCY token is selected for TCY staking operations on THORChain
                ensureTCYCoin()
                fnCallInstance = .stakeTcy(FunctionCallStakeTCY(tx: tx, vault: vault))
            case .unstakeTcy:
                // Ensure TCY token is selected for TCY unstaking operations on THORChain
                ensureTCYCoin()
                
                DispatchQueue.main.async {
                    ThorchainService.shared.fetchTcyStakedAmount(address: tx.coin.address) {
                        stakedAmount in
                        
                        DispatchQueue.main.async {
                            fnCallInstance = .unstakeTcy(FunctionCallUnstakeTCY(tx: tx, vault: vault, stakedAmount: stakedAmount))
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
                fnCallInstance = .cosmosIBC(FunctionCallCosmosIBC(tx: tx, vault: vault))
            case .merge:
                // Ensure RUNE token is selected for MERGE operations on THORChain
                ensureRuneCoin()
                fnCallInstance = .merge(FunctionCallCosmosMerge(tx: tx, vault: vault))
            case .unmerge:
                fnCallInstance = .unmerge(FunctionCallCosmosUnmerge(tx: tx, vault: vault))
            case .theSwitch:
                fnCallInstance = .theSwitch(FunctionCallCosmosSwitch(tx: tx, vault: vault))
            case .mintYRune:
                fnCallInstance = .mintYRune(FunctionCallCosmosYVault(tx: tx, vault: vault, action: .deposit, functionType: .mintYRune))
            case .mintYTCY:
                fnCallInstance = .mintYTCY(FunctionCallCosmosYVault(tx: tx, vault: vault, action: .deposit, functionType: .mintYTCY))
            case .redeemRune:
                fnCallInstance = .redeemRune(FunctionCallCosmosYVault(tx: tx, vault: vault, action: .withdraw(slippage: YVaultConstants.slippageOptions.first!), functionType: .redeemRune))
            case .redeemTCY:
                fnCallInstance = .redeemTCY(FunctionCallCosmosYVault(tx: tx, vault: vault, action: .withdraw(slippage: YVaultConstants.slippageOptions.first!), functionType: .redeemTCY))
            case .addThorLP:
                fnCallInstance = .addThorLP(FunctionCallAddThorLP(tx: tx, vault: vault))
            case .removeThorLP:
                // Ensure RUNE token is selected for REMOVE THORCHAIN LP operations on THORChain
                ensureRuneCoin()
                fnCallInstance = .removeThorLP(FunctionCallRemoveThorLP(tx: tx, vault: vault))
            case .stakeRuji:
                functionCallViewModel.setRujiToken(to: tx, vault: vault)
                fnCallInstance = .stakeRuji(FunctionCallStakeRuji(tx: tx, vault: vault))
            case .unstakeRuji:
                functionCallViewModel.setRujiToken(to: tx, vault: vault)
                fnCallInstance = .unstakeRuji(FunctionCallUnstakeRuji(tx: tx))
            case .withdrawRujiRewards:
                functionCallViewModel.setRujiToken(to: tx, vault: vault)
                fnCallInstance = .withdrawRujiRewards(FunctionCallWithdrawRujiRewards(tx: tx))
            case .securedAsset:
                fnCallInstance = .securedAsset(FunctionCallSecuredAsset(tx: tx, vault: vault))
            case .withdrawSecuredAsset:
                fnCallInstance = .withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset(tx: tx, vault: vault))
            }
        }
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
                fnCallInstance?.customErrorMessage ?? "The form is not valid. Please fix the fields marked with a red star."
            ),
            dismissButton: .default(Text("OK"))
        )
    }
    
    private func ensureRuneCoin() {
        // Ensure RUNE token is selected for operations on THORChain
        if let runeCoin = vault.runeCoin {
            tx.coin = runeCoin
        }
    }
    
    private func ensureTCYCoin() {
        if let tcyCoin = vault.tcyCoin {
            tx.coin = tcyCoin
        }
    }
    
    private func extractNodeAddress(from instance: FunctionCallInstance) -> String? {
        switch instance {
        case .bond(let bond):
            return bond.nodeAddress
        case .rebond(let rebond):
            return rebond.nodeAddress
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
                if let fnCallInstance, fnCallInstance.isTheFormValid {
                    tx.amount = fnCallInstance.amount.formatToDecimal(digits: tx.coin.decimals)
                    tx.memo = fnCallInstance.description
                    tx.memoFunctionDictionary = fnCallInstance.toDictionary()
                    tx.transactionType = fnCallInstance.getTransactionType()
                    tx.wasmContractPayload = fnCallInstance.wasmContractPayload
                    
                    if let toAddress = fnCallInstance.toAddress {
                        tx.toAddress = toAddress
                    }
                    
                    navigateToVerify = true
                    
                } else {
                    showInvalidFormAlert = true
                }
            }
        }
    }
}

private extension FunctionCallDetailsScreen {
    func setData() {
        setupForm()
        tx.coin = defaultCoin
    }
    
    func setupForm() {
        var selectedFunctionMemoType: FunctionCallType?
        var selectedContractMemoType: FunctionCallContractType?
        var fnCallInstance: FunctionCallInstance?
        
        // Temporarily disable onChange handler during setup
        let dict = tx.memoFunctionDictionary
        if let nodeAddress = dict.get("nodeAddress"), !nodeAddress.isEmpty {
            if let actionStr = dict.get("action") {
                let functionType: FunctionCallType
                
                switch actionStr.lowercased() {
                case "bond":
                    functionType = .bond
                    selectedFunctionMemoType = functionType
                    selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)
                    
                    let bondInstance = FunctionCallBond(tx: tx, vault: vault)
                    bondInstance.nodeAddress = nodeAddress
                    bondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    if let feeStr = dict.get("fee"), let feeInt = Int64(feeStr) {
                        bondInstance.fee = feeInt
                        bondInstance.feeValid = true
                    }
                    fnCallInstance = .bond(bondInstance)
                case "unbond":
                    functionType = .unbond
                    selectedFunctionMemoType = functionType
                    selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)
                    
                    let unbondInstance = FunctionCallUnbond(tx: tx, vault: vault)
                    unbondInstance.nodeAddress = nodeAddress
                    unbondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    if let amountStr = dict.get("amount"), let amountDecimal = Decimal(string: amountStr) {
                        unbondInstance.amount = amountDecimal
                        unbondInstance.amountValid = true
                    }
                    fnCallInstance = .unbond(unbondInstance)
                case "rebond":
                    functionType = .rebond
                    selectedFunctionMemoType = functionType
                    selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)
                    
                    let rebondInstance = FunctionCallReBond(tx: tx, vault: vault)
                    rebondInstance.nodeAddress = nodeAddress
                    rebondInstance.nodeAddressValid = Self.validateNodeAddress(nodeAddress)
                    if let newAddress = dict.get("newAddress") {
                        rebondInstance.newAddress = newAddress
                        rebondInstance.newAddressValid = Self.validateNodeAddress(newAddress)
                    }
                    if let amountStr = dict.get("rebondAmount"), let amountDecimal = Decimal(string: amountStr) {
                        rebondInstance.rebondAmount = amountDecimal
                        rebondInstance.rebondAmountValid = true
                    }
                    fnCallInstance = .rebond(rebondInstance)
                default:
                    break
                }
            }
        }
        
        self.selectedFunctionMemoType = selectedFunctionMemoType ?? FunctionCallType.getDefault(for: defaultCoin)
        self.selectedContractMemoType = selectedContractMemoType ?? FunctionCallContractType.getDefault(for: defaultCoin)
        self.fnCallInstance = fnCallInstance ?? FunctionCallInstance.getDefault(for: defaultCoin, tx: tx, vault: vault)
        DispatchQueue.main.async {
            self.hasCompletedInitialSetup = true
        }
    }
    
    func loadGasInfo() async {
        await functionCallViewModel.loadGasInfoForSending(tx: tx)
        await functionCallViewModel.loadFastVault(tx: tx, vault: vault)
    }
}
