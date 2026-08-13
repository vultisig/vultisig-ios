//
//  BondMayaTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import Combine
import OSLog

final class BondMayaTransactionViewModel: ObservableObject, Form {
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
    @Published var availableLPUnits: String?
    @Published var estimatedCacaoValue: Decimal?

    /// Localization key explaining why there is nothing to bond, or nil when the
    /// form is usable. Distinguishes a failed fetch — which a retry can fix —
    /// from genuinely holding no unbonded LP units, which it cannot.
    @Published private(set) var assetsUnavailableReason: String?

    /// Whether `assetsUnavailableReason` describes something a retry could
    /// change.
    var canRetryLoadingAssets: Bool {
        assetsUnavailableReason == Self.loadFailedKey
    }

    private static let loadFailedKey = "bondableAssetsLoadFailed"
    private static let noPositionsKey = "noBondableLPPositions"

    // Track if user can bond (whitelist check result)
    private var canBondToNode: Bool = true

    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        lpUnitsField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    // Use user LP positions data source - shows only pools where user has LP
    let assetsDataSource: MayaUserLPAssetsDataSource
    private let mayaAPIService = MayaChainAPIService()

    /// Available (unbonded) LP units per pool, keyed by the pool's THORChain
    /// asset. Fetched once on load; ``onAssetSelected(_:)`` reads it to install
    /// the ceiling the typed LP units are judged against.
    var userLPPositions: [String: String] = [:]

    /// The in-flight asset load, so a retry supersedes the attempt it retries
    /// instead of racing it.
    private var assetsTask: Task<Void, Never>?

    init(coin: Coin, vault: Vault, initialBondAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialBondAddress = initialBondAddress
        self.assetsDataSource = MayaUserLPAssetsDataSource(userAddress: coin.address)
        self.addressViewModel = AddressViewModel(
            coin: coin,
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
    }

    /// Validators that hold whichever pool is selected. The availability
    /// validator is layered on top once that pool's units are known, and has to
    /// come back off when the selection changes.
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

        loadAssets()

        // Watch for node address changes - check whitelist eligibility
        addressViewModel.field.$valid
            .combineLatest(addressViewModel.field.$value)
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] isValid, address in
                guard let self else { return }
                if isValid && !address.isEmpty {
                    self.checkWhitelistEligibility(nodeAddress: address)
                } else {
                    self.canBondToNode = true
                }
            }
            .store(in: &cancellables)

        // Watch for asset changes
        $selectedAsset
            .compactMap { $0 }
            .sink { [weak self] asset in
                self?.onAssetSelected(asset)
            }
            .store(in: &cancellables)

        // Watch for LP units changes (debounced)
        lpUnitsField.$value
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.validateLPUnits()
            }
            .store(in: &cancellables)
    }

    /// Check if user is whitelisted on the specified node
    private func checkWhitelistEligibility(nodeAddress: String) {
        Task {
            do {
                let isWhitelisted = try await mayaAPIService.isAddressWhitelisted(
                    nodeAddress: nodeAddress,
                    bondAddress: coin.address
                )

                await MainActor.run {
                    canBondToNode = isWhitelisted

                    if !isWhitelisted {
                        addressViewModel.field.error = "notWhitelistedOnNode".localized
                        addressViewModel.field.valid = false
                    }
                }
            } catch {
                await MainActor.run {
                    // On error, allow bonding attempt (server will reject if not whitelisted)
                    canBondToNode = true
                }
                Log.send.viewModel.error("Error checking whitelist: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Loads the user's LP positions and the bondable assets derived from them.
    ///
    /// Both are required before the form can produce a transaction, so a failure
    /// in either is reported as one — and it is reported rather than swallowed,
    /// because the DeFi tab is the only Maya bond route there is.
    func loadAssets() {
        assetsTask?.cancel()
        isLoading = true
        assetsUnavailableReason = nil

        assetsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let positions = try await fetchUserLPPositions()
                let assets = try await assetsDataSource.fetchAssets()

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isLoading = false
                    userLPPositions = positions

                    if let firstAsset = assets.first {
                        selectedAsset = firstAsset
                    } else {
                        assetsUnavailableReason = Self.noPositionsKey
                    }
                }
            } catch {
                Log.send.viewModel.error("Error loading bondable Maya assets: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isLoading = false
                    assetsUnavailableReason = Self.loadFailedKey
                }
            }
        }
    }

    /// The user's unbonded LP units per pool, keyed by pool name.
    private func fetchUserLPPositions() async throws -> [String: String] {
        async let memberDetailsTask = mayaAPIService.getMemberDetails(address: coin.address)
        async let allBondedUnitsTask = mayaAPIService.getAllBondedLPUnitsByPool(address: coin.address)

        let memberDetails = try await memberDetailsTask
        let allBondedUnits = try await allBondedUnitsTask

        var positions: [String: String] = [:]
        for pool in memberDetails.pools {
            let totalUnits = UInt64(pool.liquidityUnits) ?? 0
            let bondedUnits = allBondedUnits[pool.pool] ?? 0
            let availableUnits = totalUnits > bondedUnits ? totalUnits - bondedUnits : 0

            if availableUnits > 0 {
                positions[pool.pool] = String(availableUnits)
            }
        }
        return positions
    }

    var transactionBuilder: TransactionBuilder? {
        // Block if not whitelisted on node
        guard canBondToNode else {
            validateErrors()
            return nil
        }

        // `validateErrors()` first, not a bare `validForm` read: the tap is
        // what reveals the field errors on a form the user has not touched, and
        // it recomputes `validForm` from the validators installed *now* —
        // `LPUnitsValidator` arrives with the user's LP positions, after the
        // units may already have been typed.
        validateErrors()
        guard validForm, let selectedAsset, let lpUnits = UInt64(lpUnitsField.value) else { return nil }

        return BondMayaTransactionBuilder(
            coin: coin,
            isBond: true,
            nodeAddress: addressViewModel.field.value,
            selectedAsset: selectedAsset.thorchainAsset,
            lpUnits: lpUnits
        )
    }

    // MARK: - Validation Methods

    /// Installs the balance-aware LP-units validator for the picked pool. The
    /// asset is routinely picked *after* the units are typed, so the swap has to
    /// be enough on its own to make an over-available amount invalid.
    func onAssetSelected(_ asset: THORChainAsset) {
        // Look up LP units from cached positions (fetched from Maya API)
        guard let units = userLPPositions[asset.thorchainAsset] else {
            availableLPUnits = nil
            // The previous asset's ceiling does not apply to this one, and
            // leaving it installed would validate against the wrong pool.
            lpUnitsField.validators = Self.baseLPUnitsValidators
            return
        }

        availableLPUnits = units

        // Update validator with available units
        lpUnitsField.validators = Self.baseLPUnitsValidators + [
            LPUnitsValidator(availableUnits: units)
        ]
    }

    private func validateLPUnits() {
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
