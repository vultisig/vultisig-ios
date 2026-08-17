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

    /// An unbond ceiling, carrying the position it was measured for.
    ///
    /// The scope travels with the number deliberately. The node address
    /// reaches the fetch through a debounce, so between a paste and the
    /// refetch the address field already reads the new node while the figure
    /// still describes the old one — and the memo is built from the field. A
    /// bare `String?` cannot tell those apart; this can.
    struct BondedUnitsCeiling: Equatable {
        let nodeAddress: String
        let asset: THORChainAsset
        let units: String
    }

    // Validation state
    @Published var bondedUnitsCeiling: BondedUnitsCeiling?
    @Published var estimatedCacaoValue: Decimal?

    /// The ceiling as the screen shows it, or nil while none is known.
    var bondedLPUnits: String? { bondedUnitsCeiling?.units }

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

        // The ceiling belongs to one node. Replacing it is debounced below;
        // dropping it is not, because for the length of that debounce the
        // address field already reads the newly typed node while the figure
        // and its validator still describe the previous one.
        addressViewModel.field.$value
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                bondedUnitsTask?.cancel()
                clearBondedUnitsCeiling()
            }
            .store(in: &cancellables)

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
                    self.bondedUnitsTask?.cancel()
                    self.isLoading = false
                    self.availableBondedAssets = []
                    self.selectedAsset = nil
                    self.clearBondedUnitsCeiling()
                    self.assetsUnavailableReason = nil
                }
            }
            .store(in: &cancellables)

        // Watch for asset changes - update bonded LP units display.
        // The asset comes from the emission, not from `selectedAsset`: a
        // `@Published` publishes in `willSet`, so reading the property back
        // here still answers the PREVIOUS asset — which is the one whose
        // ceiling has to be replaced.
        $selectedAsset
            .compactMap { $0 }
            .sink { [weak self] asset in
                self?.fetchBondedLPUnits(for: asset)
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
        bondedUnitsTask?.cancel()
        clearBondedUnitsCeiling()
        assetsDataSource.nodeAddress = nodeAddress

        bondedAssetsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let assets = try await assetsDataSource.fetchAssets()

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
                    fetchBondedLPUnits(for: selectedAsset)
                } else {
                    // An asset only bonded on the PREVIOUS node must not
                    // survive the switch — unbonding it here would build a
                    // memo for a pool the user has no position in on this
                    // node.
                    selectedAsset = assets.first
                }
            } catch {
                Log.send.viewModel.error("Error fetching bonded LP positions: \(error.localizedDescription, privacy: .public)")
                guard isCurrentRequest(for: nodeAddress) else { return }
                isLoading = false
                availableBondedAssets = []
                selectedAsset = nil
                assetsUnavailableReason = "bondedAssetsLoadFailed"
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
        //
        // A ceiling is required as well, and it has to be the ceiling for the
        // position this memo names. Without one the only validators left are
        // the generic ones, which wave through any integer at all; with the
        // wrong one, the figure was measured somewhere else. Both are asked
        // for here rather than assumed from the fetch having run, because the
        // memo is assembled from the live field and the fetch that refreshes
        // the ceiling is debounced behind it.
        guard validateErrors(),
              let selectedAsset,
              let ceiling = bondedUnitsCeiling,
              ceiling.nodeAddress == addressViewModel.field.value,
              ceiling.asset == selectedAsset,
              let lpUnits = UInt64(lpUnitsField.value) else { return nil }

        return BondMayaTransactionBuilder(
            coin: coin,
            isBond: false,
            nodeAddress: addressViewModel.field.value,
            selectedAsset: selectedAsset.thorchainAsset,
            lpUnits: lpUnits
        )
    }

    // MARK: - Validation Methods

    /// Drops the unbond ceiling: both the figure the screen shows and the
    /// validator that enforces it.
    ///
    /// They are one fact and must never be half-cleared. Nulling the figure
    /// while the validator stays installed leaves the form still measuring the
    /// typed units against a pool the user is no longer unbonding from — a
    /// limit that belongs to a position they may not hold.
    private func clearBondedUnitsCeiling() {
        bondedUnitsCeiling = nil
        lpUnitsField.validators = Self.baseLPUnitsValidators
    }

    /// Reads the bonded units for one pool on the node in the address field,
    /// and installs them as the unbond ceiling.
    ///
    /// The pool is passed in rather than read from `selectedAsset`, because the
    /// caller is the `@Published` sink and that publishes in `willSet`: the
    /// property still holds the outgoing asset while this runs.
    private func fetchBondedLPUnits(for asset: THORChainAsset) {
        bondedUnitsTask?.cancel()
        // Whatever ceiling is on the field belongs to the previous selection.
        // It comes off before the request goes out, and stays off unless this
        // asset answers with a figure of its own — the alternative is a form
        // that keeps validating against a limit it has already left behind.
        clearBondedUnitsCeiling()

        guard addressViewModel.field.valid else {
            estimatedCacaoValue = nil
            return
        }

        let nodeAddress = addressViewModel.field.value

        bondedUnitsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bondedUnits = try await mayaAPIService.getBondedLPUnits(
                    nodeAddress: nodeAddress,
                    bondAddress: coin.address,
                    poolAsset: asset.thorchainAsset
                )

                guard let units = bondedUnits, units > 0 else {
                    guard isCurrentRequest(for: nodeAddress, asset: asset) else { return }
                    clearBondedUnitsCeiling()
                    return
                }

                // This figure is the unbond ceiling; publishing it for a
                // node or asset the user has since left would raise the
                // limit on a position that does not have it.
                guard isCurrentRequest(for: nodeAddress, asset: asset) else { return }
                bondedUnitsCeiling = BondedUnitsCeiling(
                    nodeAddress: nodeAddress,
                    asset: asset,
                    units: String(units)
                )

                // Update validator with bonded units
                lpUnitsField.validators = Self.baseLPUnitsValidators + [
                    LPUnitsValidator(availableUnits: String(units))
                ]
            } catch {
                Log.send.viewModel.error("Error fetching bonded LP units: \(error.localizedDescription, privacy: .public)")
                guard isCurrentRequest(for: nodeAddress, asset: asset) else { return }
                clearBondedUnitsCeiling()
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
