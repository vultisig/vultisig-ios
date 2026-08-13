//
//  UnbondMayaTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import Combine
import OSLog

final class UnbondMayaTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let initialBondAddress: String?

    @Published var validForm: Bool = false

    @Published var addressViewModel: AddressViewModel
    @Published var lpUnitsField = FormField(
        label: "lpUnits".localized,
        placeholder: "0"
    )
    @Published var selectedAsset: THORChainAsset?
    @Published var isLoading: Bool = false

    // Validation state
    @Published var bondedLPUnits: String?
    @Published var estimatedCacaoValue: Decimal?

    // Available bonded assets for the current node
    @Published var availableBondedAssets: [THORChainAsset] = []

    /// Localization key set when the bonded-asset fetch failed, as opposed to
    /// returning nothing. The empty case already reports itself on the address
    /// field ("no bonded assets found on this node") — saying that after a
    /// network failure would be a claim about the node the app never verified.
    @Published private(set) var assetsUnavailableReason: String?

    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        lpUnitsField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    // Use bonded assets data source - shows only pools bonded to the selected node
    let assetsDataSource: MayaBondedAssetsDataSource
    private let mayaAPIService = MayaChainAPIService()

    /// The in-flight bonded-asset fetch, so a new address supersedes the
    /// previous one instead of racing it.
    private var bondedAssetsTask: Task<Void, Never>?

    /// Same, for the per-asset bonded-unit lookup that sets the unbond ceiling.
    private var bondedUnitsTask: Task<Void, Never>?

    init(coin: Coin, vault: Vault, initialBondAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialBondAddress = initialBondAddress
        self.assetsDataSource = MayaBondedAssetsDataSource(bondAddress: coin.address)
        self.addressViewModel = AddressViewModel(
            coin: coin,
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
    }

    /// Validators that hold no matter which node is loaded. The availability
    /// validator is layered on top once the node answers, and has to come back
    /// off when the node changes.
    private static var baseLPUnitsValidators: [FormFieldValidator] {
        [
            RequiredValidator(errorMessage: "emptyLPsField".localized),
            IntValidator()
        ]
    }

    func onLoad() {
        setupForm()
        lpUnitsField.validators = Self.baseLPUnitsValidators

        if let initialBondAddress {
            addressViewModel.field.value = initialBondAddress
        }

        // Watch for address changes - fetch bonded assets when address is valid
        addressViewModel.field.$valid
            .combineLatest(addressViewModel.field.$value)
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .sink { [weak self] isValid, address in
                guard let self else { return }
                if isValid && !address.isEmpty {
                    self.fetchBondedAssetsForNode(address)
                } else {
                    // Drop whatever is in flight too, or its completion
                    // repopulates the fields that were just cleared.
                    self.bondedAssetsTask?.cancel()
                    self.isLoading = false
                    self.availableBondedAssets = []
                    self.selectedAsset = nil
                    self.bondedLPUnits = nil
                    self.assetsUnavailableReason = nil
                }
            }
            .store(in: &cancellables)

        // Watch for asset changes - update bonded LP units display
        $selectedAsset
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.fetchBondedLPUnits()
            }
            .store(in: &cancellables)

        // Watch for LP units changes (debounced) to calculate CACAO value
        lpUnitsField.$value
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.calculateCacaoValue()
            }
            .store(in: &cancellables)
    }

    /// Re-runs the bonded-asset fetch for the address currently in the form.
    /// Exposed so a transient failure is recoverable without backing out of the
    /// screen — this is the get-my-money-out direction.
    func retryLoadingAssets() {
        let address = addressViewModel.field.value
        guard !address.isEmpty else { return }
        fetchBondedAssetsForNode(address)
    }

    /// Fetch bonded assets for the specified node address.
    ///
    /// The address is debounced, not serialised, so two fetches can overlap.
    /// Every publish is therefore guarded on the address still being the one
    /// asked for — otherwise a slow request for a previous node could overwrite
    /// the current node's assets, or leave its own failure on screen after the
    /// user has moved on.
    private func fetchBondedAssetsForNode(_ nodeAddress: String) {
        bondedAssetsTask?.cancel()
        isLoading = true
        assetsUnavailableReason = nil
        // The bonded-unit figure and the availability validator describe the
        // node that was loaded before this one. They have to go before the new
        // node answers, or the form briefly offers the previous node's limit.
        bondedLPUnits = nil
        lpUnitsField.validators = Self.baseLPUnitsValidators
        assetsDataSource.nodeAddress = nodeAddress

        bondedAssetsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let assets = try await assetsDataSource.fetchAssets()

                await MainActor.run {
                    guard isCurrentRequest(for: nodeAddress) else { return }
                    isLoading = false
                    availableBondedAssets = assets

                    if assets.isEmpty {
                        addressViewModel.field.error = "noBondedAssetsOnNode".localized
                        selectedAsset = nil
                    } else if let selectedAsset, assets.contains(selectedAsset) {
                        // Same asset, different node: `$selectedAsset` will not
                        // fire, so nothing else would re-read the bonded units
                        // for the node now in the address field.
                        fetchBondedLPUnits()
                    } else {
                        // An asset only bonded on the PREVIOUS node must not
                        // survive the switch — unbonding it here would build a
                        // memo for a pool the user has no position in on this
                        // node.
                        selectedAsset = assets.first
                    }
                }
            } catch {
                Log.send.viewModel.error("Error fetching bonded LP positions: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard isCurrentRequest(for: nodeAddress) else { return }
                    isLoading = false
                    availableBondedAssets = []
                    selectedAsset = nil
                    assetsUnavailableReason = "bondedAssetsLoadFailed"
                }
            }
        }
    }

    /// Whether a completed fetch still describes the address on screen.
    @MainActor
    private func isCurrentRequest(for nodeAddress: String) -> Bool {
        !Task.isCancelled && addressViewModel.field.value == nodeAddress
    }

    /// As above, for results that are also scoped to one pool.
    @MainActor
    private func isCurrentRequest(for nodeAddress: String, asset: THORChainAsset) -> Bool {
        isCurrentRequest(for: nodeAddress) && selectedAsset == asset
    }

    var transactionBuilder: TransactionBuilder? {
        // Deliberately NOT `validForm`. `Form` recomputes that only when a
        // field's value publishes, and the availability validator is installed
        // later, when the node answers — so a units figure typed before the
        // ceiling arrived leaves `validForm` stale at true. Re-running the
        // validators here is what the button press is for anyway: it is also
        // what reveals the field errors.
        guard revalidate(), let selectedAsset, let lpUnits = UInt64(lpUnitsField.value) else { return nil }

        return BondMayaTransactionBuilder(
            coin: coin,
            isBond: false,
            nodeAddress: addressViewModel.field.value,
            selectedAsset: selectedAsset.thorchainAsset,
            lpUnits: lpUnits
        )
    }

    // MARK: - Validation Methods

    private func fetchBondedLPUnits() {
        guard addressViewModel.field.valid, let selectedAsset else {
            bondedLPUnits = nil
            estimatedCacaoValue = nil
            return
        }

        bondedUnitsTask?.cancel()
        let nodeAddress = addressViewModel.field.value

        bondedUnitsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bondedUnits = try await mayaAPIService.getBondedLPUnits(
                    nodeAddress: nodeAddress,
                    bondAddress: coin.address,
                    poolAsset: selectedAsset.thorchainAsset
                )

                guard let units = bondedUnits, units > 0 else {
                    await MainActor.run {
                        guard isCurrentRequest(for: nodeAddress, asset: selectedAsset) else { return }
                        bondedLPUnits = nil
                    }
                    return
                }

                await MainActor.run {
                    // This figure is the unbond ceiling; publishing it for a
                    // node or asset the user has since left would raise the
                    // limit on a position that does not have it.
                    guard isCurrentRequest(for: nodeAddress, asset: selectedAsset) else { return }
                    bondedLPUnits = String(units)

                    // Update validator with bonded units
                    lpUnitsField.validators = Self.baseLPUnitsValidators + [
                        LPUnitsValidator(availableUnits: String(units))
                    ]
                }
            } catch {
                Log.send.viewModel.error("Error fetching bonded LP units: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard isCurrentRequest(for: nodeAddress, asset: selectedAsset) else { return }
                    bondedLPUnits = nil
                }
            }
        }
    }

    private func calculateCacaoValue() {
        guard let selectedAsset,
              let lpUnitsValue = UInt64(lpUnitsField.value),
              lpUnitsValue > 0 else {
            estimatedCacaoValue = nil
            return
        }

        Task {
            do {
                let cacaoValue = try await mayaAPIService.calculateLPUnitsCacaoValue(
                    lpUnits: lpUnitsValue,
                    poolAsset: selectedAsset.thorchainAsset
                )

                await MainActor.run {
                    estimatedCacaoValue = cacaoValue
                }
            } catch {
                await MainActor.run {
                    estimatedCacaoValue = nil
                }
            }
        }
    }
}
