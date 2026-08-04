//
//  SolanaAssociatedTokenAccount.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// The two SPL token programs an associated token account can belong to. The
/// program is part of the ATA's derivation seeds, so the same owner and mint
/// produce two different addresses under the two programs.
enum SolanaTokenProgram: String, CaseIterable {
    case token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    case token2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    init?(programId: String) {
        self.init(rawValue: programId)
    }
}

/// Derivation of associated token account addresses.
///
/// This is how "did the funds go to an account the user controls?" is answered
/// without trusting anything the transaction builder said: the ATA is a program
/// address derived from the owner, the token program and the mint, so it can be
/// recomputed locally and compared.
enum SolanaAssociatedTokenAccount {

    static let programId = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    static func derive(owner: String, mint: String, tokenProgram: SolanaTokenProgram) -> String? {
        guard let address = WalletCore.SolanaAddress(string: owner) else { return nil }
        let derived: String?
        switch tokenProgram {
        case .token:
            derived = address.defaultTokenAddress(tokenMintAddress: mint)
        case .token2022:
            derived = address.token2022Address(tokenMintAddress: mint)
        }
        guard let derived, !derived.isEmpty else { return nil }
        return derived
    }

    /// Every associated token account `owner` can hold for `mint`, one per token
    /// program.
    ///
    /// A mint belongs to exactly one token program on chain, but which one is not
    /// known from the mint address alone. Both derivations are the user's own
    /// account, so treating the pair as the answer stays fail-closed against a
    /// third party's address while never rejecting the user's own.
    static func ownedAccounts(owner: String, mint: String) -> Set<String> {
        Set(SolanaTokenProgram.allCases.compactMap { derive(owner: owner, mint: mint, tokenProgram: $0) })
    }
}
