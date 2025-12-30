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
    @Published var bondValidationWarning: String?  // Soft validation warning
    @Published var bondValidationError: String?    // Hard validation error (blocks)
    @Published var availableLPUnits: String?
    @Published var estimatedCacaoValue: Decimal?
    @Published var minimumLPUnitsNeeded: UInt64?
    @Published var minimumBondRequired: Decimal = 35000

    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        lpUnitsField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    let assetsDataSource = MayaAssetsDataSource()
    private let mayaAPIService = MayaChainAPIService()
    
    init(coin: Coin, vault: Vault, initialBondAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialBondAddress = initialBondAddress
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
            let assets = await assetsDataSource.fetchAssets()
            await MainActor.run { isLoading = false }

            if let firstAsset = assets.first {
                await MainActor.run {
                    selectedAsset = firstAsset
                }
            }
        }

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
    
    var transactionBuilder: TransactionBuilder? {
        validateErrors()

        // HARD VALIDATION: Block if critical errors
        guard bondValidationError == nil else { return nil }
        guard validForm, let selectedAsset, let lpUnits = UInt64(lpUnitsField.value) else { return nil }

        // Soft validation warning doesn't block

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
        Task {
            // 1. Find LP position for this pool
            let lpPosition = vault.lpPositions.first { position in
                position.poolName == asset.thorchainAsset
            }

            guard let position = lpPosition, let units = position.poolUnits else {
                await MainActor.run {
                    availableLPUnits = nil
                    bondValidationError = "noLPPositionForPool".localized
                    minimumLPUnitsNeeded = nil
                }
                return
            }

            // 2. Calculate minimum LP units needed
            let minUnits = try? await mayaAPIService.calculateMinimumLPUnits(
                poolAsset: asset.thorchainAsset
            )

            await MainActor.run {
                availableLPUnits = units
                minimumLPUnitsNeeded = minUnits
                bondValidationError = nil

                // Update validator with available units
                lpUnitsField.validators = [
                    RequiredValidator(errorMessage: "emptyLPsField".localized),
                    IntValidator(),
                    LPUnitsValidator(availableUnits: units)
                ]
            }
        }
    }

    private func validateLPUnits() {
        guard let selectedAsset,
              let availableUnits = availableLPUnits,
              let lpUnitsValue = UInt64(lpUnitsField.value),
              lpUnitsValue > 0 else {
            estimatedCacaoValue = nil
            bondValidationWarning = nil
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

                    // SOFT VALIDATION: Warn if below minimum
                    if cacaoValue < minimumBondRequired {
                        bondValidationWarning = String(
                            format: "bondValueBelowMinimum".localized,
                            cacaoValue.formatted(),
                            minimumBondRequired.formatted()
                        )
                    } else {
                        bondValidationWarning = nil
                    }
                }
            } catch {
                await MainActor.run {
                    bondValidationWarning = "failedToCalculateBondValue".localized
                    estimatedCacaoValue = nil
                }
            }
        }
    }
}
