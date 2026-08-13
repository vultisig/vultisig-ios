import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Log.send.view

struct FunctionCallDetailsScreen: View {
    @Environment(\.router) var router
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @ObservedObject var vault: Vault

    @State private var selectedFunctionMemoType: FunctionCallType = .custom
    /// The last selection that produced a form on this screen. A migrated
    /// function has its own screen, so the selector is restored to this after
    /// routing out — otherwise the dropdown would name one function over
    /// another function's form, and re-picking the migrated one would publish
    /// no change at all.
    @State private var lastLegacyFunctionMemoType: FunctionCallType = .custom
    @State private var selectedContractMemoType: FunctionCallContractType = .thorChainMessageDeposit
    @State private var showInvalidFormAlert = false
    @State private var hasCompletedInitialSetup = false

    // Screen owns active coin / gas. After PR4 every sub-model accepts
    // the current coin at construction and mutates it through
    // `coinSelectionHandler` for the cross-mutators (AddThorLP pool
    // dropdown, WithdrawSecuredAsset asset picker).
    @State private var selectedCoin: Coin = .example
    @State private var gas: BigInt = .zero

    @State var fnCallInstance: FunctionCallInstance?
    let defaultCoin: Coin
    /// The operation this screen opens on, chosen by the action list rather
    /// than by a default. When set, the screen is *that operation's* form:
    /// both selectors are hidden and the title names it, because the choice
    /// was already made on the row the user tapped.
    let preselected: FunctionCallType?

    init(
        vault: Vault,
        defaultCoin: Coin?,
        preselected: FunctionCallType?
    ) {
        self.vault = vault
        self.defaultCoin = defaultCoin
            ?? vault.coins.first(where: { $0.isNativeToken })
            ?? Coin.example
        self.preselected = preselected
    }

    /// Hidden for a preselected operation: a dropdown that can only re-pick
    /// what the user already picked is a way back into the default-selection
    /// bugs the action list exists to delete.
    var showsSelectors: Bool {
        preselected == nil
    }

    var body: some View {
        Screen {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if showsSelectors {
                            contractSelector
                            functionSelector
                        }
                        if let instance = fnCallInstance {
                            FunctionCallContentView(instance: instance, selectedCoin: $selectedCoin)
                        }
                    }
                }
                button
            }
        }
        .screenTitle(preselected?.display() ?? "function".localized)
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
        .onChange(of: selectedFunctionMemoType) {
            guard hasCompletedInitialSetup else { return }
            guard let fnInstance = fnCallInstance else { return }
            let currentNodeAddress = extractNodeAddress(from: fnInstance)

            // Operations already on the `FunctionTransaction` architecture have
            // no sub-model to build here — they own a screen. One mapping, one
            // navigation, no per-operation branch.
            if let transactionType = selectedFunctionMemoType.migratedTransactionType(
                coin: selectedCoin,
                nodeAddress: currentNodeAddress
            ) {
                selectedFunctionMemoType = lastLegacyFunctionMemoType
                router.navigate(
                    to: FunctionCallRoute.functionTransaction(vault: vault, transactionType: transactionType)
                )
                return
            }

            lastLegacyFunctionMemoType = selectedFunctionMemoType
            buildInstance(for: selectedFunctionMemoType, nodeAddress: currentNodeAddress)
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
            title: Text("formInvalid".localized),
            message: Text(
                fnCallInstance?.customErrorMessage ?? "formInvalidDefaultMessage".localized
            ),
            dismissButton: .default(Text("ok".localized))
        )
    }

    private func ensureRuneCoin() {
        // Ensure RUNE token is selected for operations on THORChain.
        if let runeCoin = vault.runeCoin {
            selectedCoin = runeCoin
        }
    }

    /// Builds the sub-model an operation's form reads from.
    ///
    /// Two callers: a selection change on the dropdown, and the preselected
    /// operation a row navigated to. Sharing one path is what keeps a row's
    /// form identical to the one the dropdown produced.
    private func buildInstance(for type: FunctionCallType, nodeAddress: String?) {
        switch type {
        case .rebond:
            // Ensure RUNE token is selected for REBOND operations on THORChain.
            // Hoisted here per the FunctionCall sub-model rewrite —
            // ReBond is a pure value-reader, the screen owns the
            // RUNE-pin so the sub-model can drop its init-time write.
            ensureRuneCoin()
            let rebondInstance = FunctionCallReBond()

            if let nodeAddress, !nodeAddress.isEmpty {
                rebondInstance.nodeAddress = nodeAddress
            }

            fnCallInstance = .rebond(rebondInstance)
        case .bondMaya:
            DispatchQueue.main.async {
                MayachainService.shared.getDepositAssets { assetsResponse in
                    let assets = assetsResponse.map { IdentifiableString(value: $0) }
                    DispatchQueue.main.async {
                        self.fnCallInstance = .bondMaya(
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
                        self.fnCallInstance = .unbondMaya(
                            FunctionCallUnbondMayaChain(assets: assets)
                        )
                    }
                }
            }

        case .leave, .vote:
            // Migrated to `Features/FunctionTransaction/` — the action list
            // routes them to their own screens and never lands here. Listed
            // only to keep this switch exhaustive; each migration adds its
            // case name.
            break
        case .custom:
            fnCallInstance = .custom(FunctionCallCustom(coin: selectedCoin, vault: vault))
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
            fnCallInstance = .addThorLP(FunctionCallAddThorLP(coin: selectedCoin, vault: vault))
        case .securedAsset:
            fnCallInstance = .securedAsset(FunctionCallSecuredAsset(coin: selectedCoin, vault: vault))
        case .withdrawSecuredAsset:
            fnCallInstance = .withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset(coin: selectedCoin, vault: vault))
        }
    }

    private func extractNodeAddress(from instance: FunctionCallInstance) -> String? {
        switch instance {
        case .rebond(let rebond):
            return rebond.nodeAddress
        default:
            return nil
        }
    }

    var functionSelector: some View {
        FunctionCallSelectorDropdown(
            items: .constant(FunctionCallType.getCases(for: selectedCoin)),
            selected: $selectedFunctionMemoType, coin: $selectedCoin)
    }

    var contractSelector: some View {
        FunctionCallContractSelectorDropDown(
            items: .constant(
                FunctionCallContractType.getCases(for: selectedCoin)),
            selected: $selectedContractMemoType, coin: selectedCoin)
    }

    var button: some View {
        PrimaryButton(title: "continue") {
            Task {
                guard let fnCallInstance, fnCallInstance.isFormValid(for: selectedCoin) else {
                    showInvalidFormAlert = true
                    return
                }

                let immutableTx = fnCallInstance.toSendTransaction(
                    coin: selectedCoin,
                    vault: vault,
                    gas: gas
                )
                router.navigate(to: FunctionCallRoute.verify(tx: immutableTx, vault: vault))
            }
        }
    }
}

private extension FunctionCallDetailsScreen {
    /// The active coin is set first: `buildInstance(for:nodeAddress:)` pins
    /// RUNE for the operations that need it, and a later blanket assignment
    /// would undo that pin.
    func setData() {
        selectedCoin = defaultCoin
        setupForm()
    }

    func setupForm() {
        self.selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)

        if let preselected {
            // Built through the same path a selection change takes, so a
            // preselected operation gets exactly the form the dropdown built —
            // including the Maya asset fetch that `FunctionCallInstance
            // .getDefault` skips.
            self.selectedFunctionMemoType = preselected
            self.lastLegacyFunctionMemoType = preselected
            buildInstance(for: preselected, nodeAddress: nil)
        } else {
            self.selectedFunctionMemoType = FunctionCallType.getDefault(for: defaultCoin)
            self.lastLegacyFunctionMemoType = self.selectedFunctionMemoType
            self.fnCallInstance = FunctionCallInstance.getDefault(for: defaultCoin, vault: vault)
        }

        DispatchQueue.main.async {
            self.hasCompletedInitialSetup = true
        }
    }

    func loadGasInfo() async {
        let probeTx = SendTransaction.empty(coin: selectedCoin, vault: vault)
        do {
            let chainSpecific = try await BlockChainService.shared.fetchSpecific(tx: probeTx)
            gas = chainSpecific.gas
        } catch {
            logger.error("failed to fetch chain-specific data: \(error.localizedDescription, privacy: .public)")
        }
    }
}
