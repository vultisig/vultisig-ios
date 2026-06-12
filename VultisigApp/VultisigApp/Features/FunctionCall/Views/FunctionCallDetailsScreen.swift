import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-details-screen")

struct FunctionCallDetailsScreen: View {
    @Environment(\.router) var router
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @ObservedObject var vault: Vault

    @State private var selectedFunctionMemoType: FunctionCallType = .custom
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
        if let runeCoin = vault.runeCoin {
            selectedCoin = runeCoin
        }
    }

    private func ensureTCYCoin() {
        if let tcyCoin = vault.tcyCoin {
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
    func setData() {
        setupForm()
        selectedCoin = defaultCoin
    }

    func setupForm() {
        self.selectedFunctionMemoType = FunctionCallType.getDefault(for: defaultCoin)
        self.selectedContractMemoType = FunctionCallContractType.getDefault(for: defaultCoin)
        self.fnCallInstance = FunctionCallInstance.getDefault(for: defaultCoin, vault: vault)
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
