//
//  TonJettonTransferGuard.swift
//  VultisigApp
//

import Foundation
import WalletCore

enum TonJettonTransferGuardError: Error, LocalizedError, Equatable {
    case walletMismatch
    case tokenMismatch
    case lookupFailed

    var errorDescription: String? {
        switch self {
        case .walletMismatch:
            return "The jetton wallet being signed does not belong to the token shown"
        case .tokenMismatch:
            return "The token ticker or decimals do not match the jetton being signed"
        case .lookupFailed:
            return "Could not verify the TON jetton transfer"
        }
    }
}

/// Binds the jetton wallet that is signed (`tonSpecific.jettonAddress`) to the token the
/// co-signer is shown (the payload coin's master, ticker and decimals). Fails closed.
enum TonJettonTransferGuard {

    static func verify(payload: KeysignPayload, vault: Vault, service: TonService = .shared) async throws {
        let coin = payload.coin
        // TonConnect requests are decoded from their own messages, not from the coin.
        guard coin.chain == .ton, payload.signTon == nil else { return }
        guard case .Ton(_, _, _, _, let jettonAddress, _) = payload.chainSpecific else { return }
        guard !coin.isNativeToken else {
            guard jettonAddress.isEmpty else { throw TonJettonTransferGuardError.walletMismatch }
            return
        }

        do {
            guard let ownWallet = try await service.getJettonWalletAddress(ownerAddress: coin.address, masterAddress: coin.contractAddress),
                  normalized(ownWallet) == normalized(jettonAddress) else {
                throw TonJettonTransferGuardError.walletMismatch
            }

            if let known = vault.coins.first(where: { $0.chain == .ton && !$0.isNativeToken && normalized($0.contractAddress) == normalized(coin.contractAddress) }) {
                guard known.ticker == coin.ticker, known.decimals == coin.decimals else { throw TonJettonTransferGuardError.tokenMismatch }
            } else {
                // Jetton this device doesn't list: the master is the only trustworthy decimals source.
                let info = try await service.getTokenInfo(contractAddress: coin.contractAddress)
                guard info.decimals == coin.decimals else { throw TonJettonTransferGuardError.tokenMismatch }
            }
        } catch let error as TonJettonTransferGuardError {
            throw error
        } catch {
            throw TonJettonTransferGuardError.lookupFailed
        }
    }

    private static func normalized(_ address: String) -> String {
        TONAddressConverter.toUserFriendly(address: address, bounceable: true, testnet: false) ?? address
    }
}
