//
//  UnbondMayaTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import Combine

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

    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        lpUnitsField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    // Use bonded assets data source - shows only pools bonded to the selected node
    let assetsDataSource: MayaBondedAssetsDataSource
    private let mayaAPIService = MayaChainAPIService()

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

    func onLoad() {
        setupForm()
        lpUnitsField.validators = [
            RequiredValidator(errorMessage: "emptyLPsField".localized),
            IntValidator()
        ]

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
                    self.availableBondedAssets = []
                    self.selectedAsset = nil
                    self.bondedLPUnits = nil
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

    /// Fetch bonded assets for the specified node address
    private func fetchBondedAssetsForNode(_ nodeAddress: String) {
        isLoading = true
        assetsDataSource.nodeAddress = nodeAddress

        Task {
            let assets = await assetsDataSource.fetchAssets()

            await MainActor.run {
                isLoading = false
                availableBondedAssets = assets

                if assets.isEmpty {
                    addressViewModel.field.error = "noBondedAssetsOnNode".localized
                    selectedAsset = nil
                } else {
                    // Auto-select first asset if none selected
                    if selectedAsset == nil {
                        selectedAsset = assets.first
                    }
                }
            }
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()

        guard validForm, let selectedAsset, let lpUnits = UInt64(lpUnitsField.value) else { return nil }

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

        Task {
            do {
                let bondedUnits = try await mayaAPIService.getBondedLPUnits(
                    nodeAddress: addressViewModel.field.value,
                    bondAddress: coin.address,
                    poolAsset: selectedAsset.thorchainAsset
                )

                guard let units = bondedUnits, units > 0 else {
                    await MainActor.run {
                        bondedLPUnits = nil
                    }
                    return
                }

                await MainActor.run {
                    bondedLPUnits = String(units)

                    // Update validator with bonded units
                    lpUnitsField.validators = [
                        RequiredValidator(errorMessage: "emptyLPsField".localized),
                        IntValidator(),
                        LPUnitsValidator(availableUnits: String(units))
                    ]
                }
            } catch {
                await MainActor.run {
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
