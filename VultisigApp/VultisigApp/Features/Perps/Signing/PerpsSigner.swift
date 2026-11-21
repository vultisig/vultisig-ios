//
//  PerpsSigner.swift
//  VultisigApp
//
//  One protocol, two signers:
//    - `VaultPerpsSigner` never signs. It builds the `CustomMessagePayload`
//      (`eth_signTypedData_v4`) that the existing keysign flow
//      (KeysignReviewSheet -> SigningRoute pair -> keysign -> done) already
//      signs for dApp typed data. No new signing flow or UI exists for perps.
//    - `LocalAgentPerpsSigner` signs L1 actions (orders, leverage) with a
//      device-local agent key that the vault has to approve once through
//      `approveAgent`. It refuses user-signed actions: an agent can trade but
//      must never move funds or approve other agents.
//
//  Status: nothing calls `/exchange` yet. No signature produced here is ever sent.
//

import Foundation
import WalletCore

enum PerpsSignRequest: Equatable, Sendable {
    /// Orders, leverage updates, cancels: phantom-agent signature.
    case l1(action: HLValue, nonce: UInt64, isMainnet: Bool, vaultAddress: String?, expiresAfter: UInt64? = nil)
    /// approveAgent, approveBuilderFee, withdraw, transfers: vault-only.
    case userSigned(HLUserSignedAction)

    func typedData() throws -> HLTypedData {
        switch self {
        case let .l1(action, nonce, isMainnet, vaultAddress, expiresAfter):
            return try HLActionHasher.l1TypedData(
                action: action, nonce: nonce, isMainnet: isMainnet, vaultAddress: vaultAddress, expiresAfter: expiresAfter
            )
        case .userSigned(let userSigned):
            return userSigned.typedData
        }
    }

    var isUserSigned: Bool {
        if case .userSigned = self { return true }
        return false
    }
}

struct HLSignature: Equatable, Sendable {
    let r: String
    let s: String
    let v: Int

    init(r: String, s: String, v: Int) {
        self.r = r
        self.s = s
        self.v = v
    }

    /// From a 65-byte `r ‖ s ‖ recId` secp256k1 signature.
    init?(recoverable signature: Data) {
        guard signature.count == 65 else { return nil }
        r = "0x" + signature.prefix(32).hexString
        s = "0x" + signature.dropFirst(32).prefix(32).hexString
        v = Int(signature[signature.startIndex + 64]) + 27
    }
}

enum PerpsSigningOutcome {
    /// Hand to the existing vault keysign flow; the digest it signs is `expectedDigest`.
    case vaultKeysign(CustomMessagePayload, expectedDigest: Data)
    case signed(HLSignature, digest: Data)
}

enum PerpsSignerError: Error, Equatable {
    case agentCannotSignUserAction
    case signingFailed
}

protocol PerpsSigner: Sendable {
    func prepare(_ request: PerpsSignRequest) throws -> PerpsSigningOutcome
}

struct VaultPerpsSigner: PerpsSigner {
    let vaultPublicKeyECDSA: String
    let vaultLocalPartyID: String
    /// Which vault address signs. `.trading` sets the payload's `derivePath`;
    /// `.main` leaves it nil so main-path payloads encode exactly as before.
    var account: PerpsSignerAccount = .main

    func prepare(_ request: PerpsSignRequest) throws -> PerpsSigningOutcome {
        let typedData = try request.typedData()
        var payload = CustomMessagePayload(
            method: "eth_signTypedData_v4",
            message: typedData.signTypedDataV4JSON,
            vaultPublicKeyECDSA: vaultPublicKeyECDSA,
            vaultLocalPartyID: vaultLocalPartyID,
            // Hyperliquid recovers the signer as the address of the signing key.
            chain: Chain.ethereum.name
        )
        if account == .trading { payload.derivePath = account.derivationPath }
        return .vaultKeysign(payload, expectedDigest: typedData.digest)
    }
}

struct LocalAgentPerpsSigner: PerpsSigner {
    private let privateKeyData: Data

    init(privateKeyData: Data) {
        self.privateKeyData = privateKeyData
    }

    var address: String? {
        guard let key = PrivateKey(data: privateKeyData) else { return nil }
        return CoinType.ethereum.deriveAddress(privateKey: key).lowercased()
    }

    func prepare(_ request: PerpsSignRequest) throws -> PerpsSigningOutcome {
        guard !request.isUserSigned else { throw PerpsSignerError.agentCannotSignUserAction }
        let digest = try request.typedData().digest
        guard let key = PrivateKey(data: privateKeyData),
              let raw = key.sign(digest: digest, curve: .secp256k1),
              let signature = HLSignature(recoverable: raw) else {
            throw PerpsSignerError.signingFailed
        }
        return .signed(signature, digest: digest)
    }
}
