//
//  QBTCClaimRoute.swift
//  VultisigApp
//

enum QBTCClaimRoute: Hashable {
    case pair(
        vault: Vault,
        keysignPayload: KeysignPayload,
        session: KeysignSessionInfo,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo]
    )
    /// `session` is `nil` for FastVault (orchestrator wakes Vultiserver),
    /// non-nil for SecureVault (the pair screen already produced the
    /// session + participants list via the QR handshake).
    case keysign(
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo],
        fastVaultPassword: String?,
        session: KeysignSessionInfo?,
        participants: [String]
    )
    case done(
        result: QBTCClaimRunResult,
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin
    )
}
