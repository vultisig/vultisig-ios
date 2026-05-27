import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-details-screen")

struct FunctionCallDetailsScreen: View {
    @Environment(\.router) var router
    @StateObject private var tx = FunctionCallForm()
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @ObservedObject var vault: Vault

    @State private var selectedFunctionMemoType: FunctionCallType = .custom
    @State private var selectedContractMemoType: FunctionCallContractType = .thorChainMessageDeposit
    @State private var showInvalidFormAlert = false
    @State private var hasCompletedInitialSetup = false

    // C-2a foundation — screen owns active coin / gas / fast-vault flag.
    // Sub-models still read/write `tx.coin` during the transitional period;
    // `.onChange(of: tx.coin)` dual-writes `selectedCoin` so the new shape
    // shadows the legacy form-state until C-2b → C-2e migrate per sub-model.
    @State private var selectedCoin: Coin = .example
    @State private var gas: BigInt = .zero
    @State private var isFastVault: Bool = false

    @State var fnCallInstance: FunctionCallInstance?
    let defaultCoin: Coin

    init(
        vault: Vault,
        defaultCoin: Coin?
    ) {
        self.vault = vault
        self.defaultCoin = defaultCoin
            ?? vault.coins.first(where: { $0.isNativeToken })
            ?? Coin.example
    }

    private static func validateNodeAddress(_ address: String) -> Bool {
        return AddressService.validateAddress(address: address, chain: .thorChain) ||
        AddressService.validateAddress(address: address, chain: .mayaChain) ||
        AddressService.validateAddress(address: address, chain: .ton)
    }

    var body: some View {
        Screen {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        contractSelector
                        functionSelector
                        if let instance = fnCallInstance {
                            FunctionCallContentView(instance: instance, selectedCoin: $selectedCoin)
                        }
                    }
                }
                button
            }
        }
        .screenTitle("function".localized)
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
        .onChange(of: selectedCoin) {
            Task {
                await loadGasInfo()
            }
        }
        // Transitional shim (C-2a): sub-models still mutate `tx.coin` from
        // dropdowns. Mirror those writes into the screen-owned
        // `selectedCoin` so the new state shadows the legacy form-state
        // until C-2b → C-2e migrate each sub-model to a `@Binding<Coin>`.
        .onChange(of: tx.coin) {
            if selectedCoin != tx.coin {
                selectedCoin = tx.coin
            }
        }
        .onChange(of: selectedFunctionMemoType) {
            guard hasCompletedInitialSetup else { return }
            guard let fnInstance = fnCallInstance else { return }
            let currentNodeAddress = extractNodeAddress(from: fnInstance)
            switch selectedFunctionMemoType {
            case .rebond:
                // Ensure RUNE token is selected for REBOND operations on THORChain.
                // Hoisted here per the FunctionCall sub-model rewrite —
                // ReBond is a pure value-reader, the screen owns the
                // RUNE-pin so the sub-model can drop its init-time write.
                ensureRuneCoin()
                let rebondInstance = FunctionCallReBond()

                if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                    rebondInstance.nodeAddress = nodeAddress
                }

                fnCallInstance = .rebond(rebondInstance)
            case .bondMaya:
                DispatchQueue.main.async {
                    MayachainService.shared.getDepositAssets { assetsResponse in
                        let assets = assetsResponse.map { IdentifiableString(value: $0) }
                        DispatchQueue.main.async {
                            fnCallInstance = .bondMaya(
                                FunctionCallBondMayaChain(assets: assets)
                            )
                        }
                    }
                }

            case .unbondMaya:
                DispatchQueue.main.async {
                    MayachainService.shared.getDepositAssets { assetsResponse in
                        let assets = assetsResponse.map { IdentifiableString(value: $0) }
                        DispatchQueue.main.async {
                            fnCallInstance = .unbondMaya(
                                FunctionCallUnbondMayaChain(assets: assets)
                            )
                        }
                    }
                }

            case .leave:
                // Ensure RUNE token is selected for LEAVE operations on THORChain
                ensureRuneCoin()
                let leaveInstance = FunctionCallLeave()

                if let nodeAddress = currentNodeAddress, !nodeAddress.isEmpty {
                    leaveInstance.nodeAddress = nodeAddress
                }

                fnCallInstance = .leave(leaveInstance)
            case .custom:
                fnCallInstance = .custom(FunctionCallCustom(coin: selectedCoin, vault: vault))
            case .vote:
                fnCallInstance = .vote(FunctionCallVote())
            case .stake:
                fnCallInstance = .stake(FunctionCallStake(initialAmount: selectedCoin.balanceDecimal))

            case .unstake:
                fnCallInstance = .unstake(FunctionCallUnstake())

            case .cosmosIBC:
                fnCallInstance = .cosmosIBC(FunctionCallCosmosIBC(coin: selectedCoin, vault: vault))
            case .merge:
                // Ensure RUNE token is selected for MERGE operations on THORChain
                ensureRuneCoin()
                fnCallInstance = .merge(FunctionCallCosmosMerge(coin: selectedCoin, vault: vault))
            case .unmerge:
                fnCallInstance = .unmerge(FunctionCallCosmosUnmerge(coin: selectedCoin, vault: vault))
            case .theSwitch:
                fnCallInstance = .theSwitch(FunctionCallCosmosSwitch(coin: selectedCoin, vault: vault))
            case .addThorLP:
                fnCallInstance = .addThorLP(FunctionCallAddThorLP(tx: tx, vault: vault))
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
        // Ensure RUNE token is selected for operations on THORChain.
        // PR2: also writes `selectedCoin` so the new screen-owned coin
        // state stays in sync with the legacy `tx.coin` reference until
        // PR3 removes `tx`.
        if let runeCoin = vault.runeCoin {
            tx.coin = runeCoin
            selectedCoin = runeCoin
        }
    }

    private func ensureTCYCoin() {
        if let tcyCoin = vault.tcyCoin {
            tx.coin = tcyCoin
            selectedCoin = tcyCoin
        }
    }

    private func extractNodeAddress(from instance: FunctionCallInstance) -> String? {
        switch instance {
        case .rebond(let rebond):
            return rebond.nodeAddress
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
                guard let fnCallInstance, fnCallInstance.isTheFormValid else {
                    showInvalidFormAlert = true
                    return
                }

                // PR2: 12 migrated sub-models build the immutable
                // SendTransaction directly via `toSendTransaction(...)`.
                // The 3 heavy sub-models (AddThorLP, SecuredAsset,
                // WithdrawSecuredAsset) still return nil here and fall
                // through to the legacy `tx`-mutation path until PR3
                // migrates them.
                if let migratedTx = fnCallInstance.toSendTransaction(
                    coin: selectedCoin,
                    vault: vault,
                    gas: gas,
                    isFastVault: isFastVault
                ) {
                    router.navigate(to: FunctionCallRoute.verify(tx: migratedTx, vault: vault))
                    return
                }

                tx.amount = fnCallInstance.amount.formatToDecimal(digits: tx.coin.decimals)
                tx.memo = fnCallInstance.description
                tx.memoFunctionDictionary = fnCallInstance.toDictionary()
                tx.transactionType = fnCallInstance.getTransactionType()
                tx.wasmContractPayload = fnCallInstance.wasmContractPayload

                if let toAddress = fnCallInstance.toAddress {
                    tx.toAddress = toAddress
                }

                let immutableTx = SendTransaction.fromForm(tx, vault: vault)
                router.navigate(to: FunctionCallRoute.verify(tx: immutableTx, vault: vault))
            }
        }
    }
}

private extension FunctionCallDetailsScreen {
    func setData() {
        setupForm()
        tx.vault = vault
        tx.coin = defaultCoin
        selectedCoin = defaultCoin
        isFastVault = vault.isFastVault
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
                case "rebond":
                    functionType = .rebond
                    selectedFunctionMemoType = functionType
                    selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)

                    let rebondInstance = FunctionCallReBond()
                    rebondInstance.nodeAddress = nodeAddress
                    if let newAddress = dict.get("newAddress") {
                        rebondInstance.newAddress = newAddress
                    }
                    if let amountStr = dict.get("rebondAmount"), let amountDecimal = Decimal(string: amountStr) {
                        rebondInstance.rebondAmount = amountDecimal
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
        // C-2a: screen-owned `selectedCoin` drives the chain-specific fetch.
        // `tx.coin` is dual-written from `selectedCoin` to keep un-migrated
        // sub-models in sync until C-2b → C-2e migrate each one.
        if tx.coin != selectedCoin {
            tx.coin = selectedCoin
        }
        do {
            let chainSpecific = try await BlockChainService.shared.fetchSpecific(tx: tx)
            gas = chainSpecific.gas
            tx.gas = chainSpecific.gas
        } catch {
            logger.error("failed to fetch chain-specific data: \(error.localizedDescription, privacy: .public)")
        }
    }
}
