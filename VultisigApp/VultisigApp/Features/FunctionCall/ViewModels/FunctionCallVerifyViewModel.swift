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

            // LP add transactions are deposits, not swaps. We only need to build an
            // ERC20 approve payload when the LP asset is an ERC20 token routed through
            // a THORChain router; the deposit itself is driven by the memo and
            // `isDeposit` on the chain-specific, matching Android's payload shape.
            var approvePayload: ERC20ApprovePayload?
            if tx.memoFunctionDictionary.get("pool") != nil,
               tx.coin.shouldApprove,
               !tx.toAddress.isEmpty {
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
