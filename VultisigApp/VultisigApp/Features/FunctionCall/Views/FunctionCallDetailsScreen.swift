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
    // dropdown, WithdrawSecuredAsset asset picker).
    @State private var selectedCoin: Coin = .example
    @State private var gas: BigInt = .zero

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

    var body: some View {
        Screen {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
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
            case .leave:
                // Migrated to `Features/FunctionTransaction/` — the route-out
                // above already handled it. Listed only to keep this switch
                // exhaustive; each migration adds its case name here.
                break
            case .custom:
                fnCallInstance = .custom(FunctionCallCustom(coin: selectedCoin, vault: vault))
            case .vote:
                fnCallInstance = .vote(FunctionCallVote())
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
        //
        // Only on THORChain. LEAVE is offered on MayaChain too, and swapping the
        // coin there would move the transaction onto a different chain behind
        // the user — rewriting the function selector's own case list along with
        // it, and signing LEAVE against RUNE for a node the user named on Maya.
        guard selectedCoin.chain == .thorChain, let runeCoin = vault.runeCoin else { return }
        selectedCoin = runeCoin
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
    func setData() {
        setupForm()
        selectedCoin = defaultCoin
    }

    func setupForm() {
        self.selectedFunctionMemoType = FunctionCallType.getDefault(for: defaultCoin)
        self.lastLegacyFunctionMemoType = self.selectedFunctionMemoType
        self.fnCallInstance = FunctionCallInstance.getDefault(for: defaultCoin, vault: vault)
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
