//
//  THORChainSwapPayload.swift
//  VoltixApp
//

import Foundation
import WalletCore

class THORChainSwapPayload {
    let fromAddress: String
    let fromAsset: THORChainSwapAsset
    let toAsset: THORChainSwapAsset
    let toAddress: String
    let vaultAddress: String
    let routerAddress: String?
    let fromAmount: String
    let toAmountLimit: String

    init(fromAddress: String, fromAsset: THORChainSwapAsset, toAsset: THORChainSwapAsset, toAddress: String, vaultAddress: String, routerAddress: String?, fromAmount: String, toAmountLimit: String) {
        self.fromAddress = fromAddress
        self.fromAsset = fromAsset
        self.toAsset = toAsset
        self.toAddress = toAddress
        self.vaultAddress = vaultAddress
        self.routerAddress = routerAddress
        self.fromAmount = fromAmount
        self.toAmountLimit = toAmountLimit
    }
}
