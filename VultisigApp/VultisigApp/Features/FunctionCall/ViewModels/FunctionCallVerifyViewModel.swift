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

    func createKeysignPayload(tx: SendTransaction) async throws -> KeysignPayload {
        let vault = tx.vault
        await MainActor.run { isLoading = true }
        defer {
            Task { @MainActor in isLoading = false }
        }
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)

            let keysignPayloadFactory = KeysignPayloadFactory()

            // LP adds and SECURE+ mints are deposits, not swaps. Native RUNE/CACAO
            // build their deposit from the memo in THORChainHelper and need no
            // payload. ERC20 deposits still ride the legacy swap-signing path via
            // the shared router-deposit shim. The shim is extracted into
            // `ThorchainRouterDepositBuilder` so the inline swap SECURE+ path
            // reuses the identical construction. TODO: replace with a dedicated
            // deposit payload across iOS/Android/Windows.
            let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(tx: tx)

            let basePayload = try await keysignPayloadFactory.buildTransfer(
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

            // Cosmos staking branch — `buildTransfer` defaults `signData` to
            // nil, which downstream resolves to MsgSend. For delegate /
            // undelegate / redelegate / withdrawRewards we need a SignDoc
            // carrying the proto-encoded Cosmos staking message instead, or
            // the chain rejects with a bech32-prefix mismatch on the
            // validator address. Mirrors `SendCryptoVerifyLogic`.
            //
            // Both secp256k1 chains and QBTC ship the SignDoc via
            // `signData.signDirect` — it's the one field that round-trips
            // through the proto, so the peer device rebuilds the identical
            // SignDoc hash. The only difference is the AuthInfo pubkey type:
            // QBTC's resolver path stamps `/cosmos.crypto.mldsa.PubKey`
            // (post-quantum) instead of secp256k1, and `QBTCHelper` consumes
            // those `signDirect` bytes directly rather than via WalletCore.
            if tx.cosmosStakingPayload != nil {
                let signDirect = tx.coin.chain == .qbtc
                    ? try CosmosStakingSignDataResolver.resolveMLDSA(
                        sendTransaction: tx,
                        chainSpecific: chainSpecific
                    )
                    : try CosmosStakingSignDataResolver.resolve(
                        sendTransaction: tx,
                        chainSpecific: chainSpecific
                    )
                return basePayload.withSignData(.signDirect(signDirect))
            }

            // Solana native-staking branch — build the unsigned delegate tx
            // once (pinned blockhash + derived stake-account address) and relay
            // it via `signData = .signSolana`, the field that round-trips so the
            // peer device signs byte-identical message bytes. Mirrors
            // `SendCryptoVerifyLogic`.
            if let solanaStakingPayload = tx.solanaStakingPayload {
                let payloadWithStaking = basePayload.withSolanaStakingPayload(solanaStakingPayload)
                let signSolana = try await SolanaStakingVerifyResolver.resolve(
                    payload: solanaStakingPayload,
                    basePayload: payloadWithStaking,
                    coin: tx.coin
                )
                return payloadWithStaking.withSignData(.signSolana(signSolana))
            }

            return basePayload
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
            throw HelperError.runtimeError(errorMessage)
        }
    }

    func scan(transaction: SendTransaction) async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
