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
    
    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        lpUnitsField
    ]
    
    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    
    let assetsDataSource = MayaAssetsDataSource()
    
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
        lpUnitsField.validators.append(IntValidator())
        lpUnitsField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))
        
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
    }
    
    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, let selectedAsset else { return nil }
        
        return BondMayaTransactionBuilder(
            coin: coin,
            isBond: true,
            nodeAddress: addressViewModel.field.value,
            selectedAsset: selectedAsset.thorchainAsset,
            lpUnits: UInt64(lpUnitsField.value) ?? 0
        )
    }
}
