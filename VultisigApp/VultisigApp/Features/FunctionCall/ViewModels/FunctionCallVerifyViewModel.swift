//
//  DepositVerifyViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI
import BigInt
import WalletCore

@MainActor
class FunctionCallVerifyViewModel: ObservableObject {
    let securityScanViewModel = SecurityScannerViewModel()
    @Published var isLoading = false

    // General
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var isHackedOrPhished = false

    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle

    let blockChainService = BlockChainService.shared

    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }

    func createKeysignPayload(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        await MainActor.run { isLoading = true }
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)

            let keysignPayloadFactory = KeysignPayloadFactory()

            // LP adds and SECURE+ mints are deposits, not swaps. Native RUNE/CACAO
            // build their deposit from the memo in THORChainHelper and need no
            // payload. ERC20 deposits still ride the legacy swap-signing path —
            // EVMHelper.getSwapPreSignedInputData requires a THORChainSwapPayload
            // to build the router's depositWithExpiry call (which is what carries
            // the memo to THORChain), so we synthesize one for those cases. The
            // router routes by memo, so the same shim works for both. TODO:
            // replace with a dedicated deposit payload across iOS/Android/Windows.
            var approvePayload: ERC20ApprovePayload?
            var swapPayload: SwapPayload?
            let isLPAdd = tx.memoFunctionDictionary.get("pool") != nil
            let isSecuredAssetMint = tx.memo.hasPrefix("SECURE+")
            let isRouterDeposit = isLPAdd || isSecuredAssetMint
            if isRouterDeposit, tx.coin.shouldApprove, !tx.toAddress.isEmpty {
                let inboundAddresses = await ThorchainService.shared.fetchThorchainInboundAddress()
                let chainName = ThorchainService.getInboundChainName(for: tx.coin.chain)
                guard let inbound = inboundAddresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
                    throw HelperError.runtimeError("Failed to find inbound address for \(chainName)")
                }

                let expirationTime = Date().addingTimeInterval(60 * 15)
                let thorchainSwapPayload = THORChainSwapPayload(
                    fromAddress: tx.fromAddress,
                    fromCoin: tx.coin,
                    toCoin: tx.coin,
                    vaultAddress: inbound.address,
                    routerAddress: inbound.router,
                    fromAmount: tx.amountInRaw,
                    toAmountDecimal: tx.coin.decimal(for: tx.amountInRaw),
                    toAmountLimit: "",
                    streamingInterval: "",
                    streamingQuantity: "",
                    expirationTime: UInt64(expirationTime.timeIntervalSince1970),
                    isAffiliate: false
                )
                swapPayload = tx.coin.chain == .mayaChain
                    ? .mayachain(thorchainSwapPayload)
                    : .thorchain(thorchainSwapPayload)

                approvePayload = ERC20ApprovePayload(
                    amount: tx.amountInRaw,
                    spender: tx.toAddress
                )
            }

            await MainActor.run { isLoading = false }
            return try await keysignPayloadFactory.buildTransfer(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo,
                chainSpecific: chainSpecific,
                swapPayload: swapPayload,
                approvePayload: approvePayload,
                vault: vault,
                wasmExecuteContractPayload: tx.wasmContractPayload
            )
        } catch {
            let errorMessage: String
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                errorMessage = "notEnoughBalanceError"
            case KeysignPayloadFactory.Errors.notEnoughUTXOError:
                errorMessage = "notEnoughUTXOError"
            case KeysignPayloadFactory.Errors.utxoTooSmallError:
                errorMessage = "utxoTooSmallError"
            case KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                errorMessage = "utxoSelectionFailedError"
            case KeysignPayloadFactory.Errors.failToGetSequenceNo:
                errorMessage = "failToGetSequenceNo"
            case KeysignPayloadFactory.Errors.failToGetAccountNumber:
                errorMessage = "failToGetAccountNumber"
            case KeysignPayloadFactory.Errors.failToGetRecentBlockHash:
                errorMessage = "failToGetRecentBlockHash"
            default:
                errorMessage = error.localizedDescription
            }
            await MainActor.run { isLoading = false }
            throw HelperError.runtimeError(errorMessage)
        }
    }

    func scan(transaction: SendTransaction, vault: Vault) async {
        await securityScanViewModel.scan(transaction: transaction, vault: vault)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
