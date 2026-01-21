//
//  BondMayaTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import Combine

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

    // Cache user's LP positions for quick lookup
    private var userLPPositions: [String: String] = [:] // poolName -> lpUnits
    
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
    
    func onLoad() {
        isLoading = true
        setupForm()
        lpUnitsField.validators = [
            RequiredValidator(errorMessage: "emptyLPsField".localized),
            IntValidator()
        ]

        if let initialBondAddress {
            addressViewModel.field.value = initialBondAddress
        }

        Task {
            // Fetch user's LP positions and cache them
            await fetchAndCacheUserLPPositions()

            let assets = await assetsDataSource.fetchAssets()
            await MainActor.run {
                isLoading = false

                if let firstAsset = assets.first {
                    selectedAsset = firstAsset
                }
            }
        }

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
                print("Error checking whitelist: \(error.localizedDescription)")
            }
        }
    }

    /// Fetch user's LP positions from Maya API and cache for quick lookup
    private func fetchAndCacheUserLPPositions() async {
        do {
            let memberDetails = try await mayaAPIService.getMemberDetails(address: coin.address)

            var positions: [String: String] = [:]
            for pool in memberDetails.pools {
                let units = pool.liquidityUnits
                if let unitsInt = Int64(units), unitsInt > 0 {
                    positions[pool.pool] = units
                }
            }
            let p = positions
            await MainActor.run {
                userLPPositions = p
            }
        } catch {
            print("Error fetching user LP positions: \(error.localizedDescription)")
        }
    }
    
    var transactionBuilder: TransactionBuilder? {
        validateErrors()

        // Block if not whitelisted on node
        guard canBondToNode else { return nil }

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

    private func onAssetSelected(_ asset: THORChainAsset) {
        // Look up LP units from cached positions (fetched from Maya API)
        guard let units = userLPPositions[asset.thorchainAsset] else {
            availableLPUnits = nil
            return
        }

        availableLPUnits = units

        // Update validator with available units
        lpUnitsField.validators = [
            RequiredValidator(errorMessage: "emptyLPsField".localized),
            IntValidator(),
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
