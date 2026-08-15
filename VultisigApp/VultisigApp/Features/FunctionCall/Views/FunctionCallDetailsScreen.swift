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
    @State private var showInvalidFormAlert = false
    @State private var hasCompletedInitialSetup = false

    // Screen owns active coin / gas. After PR4 every sub-model accepts
    // the current coin at construction and mutates it through
    // `coinSelectionHandler` for the cross-mutators (AddThorLP pool
    // dropdown).
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
        .withLoading(isLoading: $functionCallViewModel.isLoading)
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

            // Operations already on the `FunctionTransaction` architecture have
            // no sub-model to build here — they own a screen. One mapping, one
            // navigation, no per-operation branch.
            if let transactionType = selectedFunctionMemoType.migratedTransactionType(
                coin: selectedCoin,
                // Rebond was the last sub-model this screen read a node
                // address out of, so there is nothing left here to carry over.
                // The parameter stays as the pre-fill hook for the callers
                // that replace this dropdown.
                nodeAddress: nil
            ) {
                selectedFunctionMemoType = lastLegacyFunctionMemoType
                router.navigate(
                    to: FunctionCallRoute.functionTransaction(vault: vault, transactionType: transactionType)
                )
                return
            }

            lastLegacyFunctionMemoType = selectedFunctionMemoType
            buildInstance(for: selectedFunctionMemoType)
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

    /// Builds the sub-model an operation's form reads from.
    ///
    /// Two callers: a selection change on the dropdown, and the preselected
    /// operation a row navigated to. Sharing one path is what keeps a row's
    /// form identical to the one the dropdown produced.
    private func buildInstance(for type: FunctionCallType) {
        switch type {
        case .leave, .theSwitch, .merge, .rebond, .unmerge, .withdrawSecuredAsset, .vote, .cosmosIBC:
            // Migrated to `Features/FunctionTransaction/` — the action list
            // routes it to its own screen and never lands here. Listed only to
            // keep this switch exhaustive; each migration adds its case name.
            break
        case .custom:
            fnCallInstance = .custom(FunctionCallCustom(coin: selectedCoin, vault: vault))
        case .addThorLP:
            fnCallInstance = .addThorLP(FunctionCallAddThorLP(coin: selectedCoin, vault: vault))
        }
    }

    var functionSelector: some View {
        FunctionCallSelectorDropdown(
            items: .constant(FunctionCallType.getCases(for: selectedCoin)),
            selected: $selectedFunctionMemoType, coin: $selectedCoin)
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
                // Priced from the built transaction, not from the probe: this
                // is the figure the user approves, and nothing downstream of
                // Verify re-resolves it for display.
                let pricedTx = await functionCallViewModel.pricedForVerify(immutableTx)
                router.navigate(to: FunctionCallRoute.verify(tx: pricedTx, vault: vault))
            }
        }
    }
}

private extension FunctionCallDetailsScreen {
    /// The active coin is set first: `buildInstance(for:)` pins RUNE for the
    /// operations that need it, and a later blanket assignment would undo
    /// that pin.
    func setData() {
        selectedCoin = defaultCoin
        setupForm()
    }

    func setupForm() {
        if let preselected {
            // Built through the same path a selection change takes, so a
            // preselected operation gets exactly the form the dropdown built.
            self.selectedFunctionMemoType = preselected
            self.lastLegacyFunctionMemoType = preselected
            buildInstance(for: preselected)
        } else {
            self.selectedFunctionMemoType = FunctionCallType.getDefault(for: defaultCoin)
            self.lastLegacyFunctionMemoType = self.selectedFunctionMemoType
            self.fnCallInstance = FunctionCallInstance.getDefault(for: defaultCoin, vault: vault)
        }

        DispatchQueue.main.async {
            self.hasCompletedInitialSetup = true
        }
    }

    /// A per-unit gas figure for the coin, fetched as the form is filled.
    ///
    /// This is a PROBE — an empty transaction with no memo, amount or recipient
    /// — so on EVM it prices a bare transfer, not the call being built. It is
    /// carried into the built transaction only as the value a chain that quotes
    /// a flat gas already has; the figure Verify discloses is resolved from the
    /// real transaction on Continue, by `FunctionCallViewModel.pricedForVerify`.
    /// Keeping it means a failed pricing call falls back to what the screen
    /// showed before rather than to zero.
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
