//
//  FunctionCallBondMayaChain.swift
//  VultisigApp
//
//  Maya BOND memo sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns selectedAsset / fee /
//  nodeAddress directly. The matching `BondMayaFormView` is co-located
//  in this file.
//

import BigInt
import Foundation
import SwiftUI

struct IdentifiableString: Identifiable, Equatable {
    let id = UUID()
    let value: String
}

@Observable
@MainActor
final class FunctionCallBondMayaChain {
    var amount: Decimal = 1
    var nodeAddress: String = ""
    var fee: Int64 = .zero
    var selectedAsset: IdentifiableString
    var assets: [IdentifiableString] = []
    var addressError: String?
    var customErrorMessage: String?

    @ObservationIgnored private let assetPlaceholder = "assetLabel".localized

    init(assets: [IdentifiableString]?) {
        self.selectedAsset = .init(value: "assetLabel".localized)
        if let assets {
            self.assets = assets
        } else {
            Task { @MainActor [weak self] in
                let response = await Self.loadAssets()
                self?.assets = response
            }
        }
    }

    private static func loadAssets() async -> [IdentifiableString] {
        await withCheckedContinuation { continuation in
            MayachainService.shared.getDepositAssets { assetsResponse in
                continuation.resume(returning: assetsResponse.map { IdentifiableString(value: $0) })
            }
        }
    }

    var isAssetSelected: Bool {
        selectedAsset.value.lowercased() != assetPlaceholder.lowercased()
    }

    var isTheFormValid: Bool {
        FunctionCallAddressValidation.isValidThorMayaTON(nodeAddress) &&
        isAssetSelected
    }

    func handle(addressResult: AddressResult?) {
        guard let addressResult else { return }
        nodeAddress = addressResult.address
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "BOND:\(selectedAsset.value):\(fee):\(nodeAddress)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("asset", selectedAsset.value)
        dict.set("LPUNITS", "\(fee)")
        dict.set("nodeAddress", nodeAddress)
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct BondMayaFormView: View {
    @Bindable var model: FunctionCallBondMayaChain
    let coin: Coin

    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: .constant(model.assets),
                selected: $model.selectedAsset,
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    model.selectedAsset = asset
                }
            )

            StyledIntegerField(
                placeholder: "lpUnitsLabel".localized,
                value: $model.fee,
                format: .number,
                isValid: .constant(true)
            )

            AddressTextField(
                address: $model.nodeAddress,
                label: "nodeAddress".localized,
                coin: coin,
                error: $model.addressError
            ) { result in
                model.handle(addressResult: result)
            }
        }
    }
}
