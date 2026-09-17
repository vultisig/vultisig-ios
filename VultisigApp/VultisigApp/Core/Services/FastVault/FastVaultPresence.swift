import Foundation

/// `absent` is reserved for authoritative results. The current server contract
/// cannot produce it: neither a legacy 400 nor a generic 404 proves absence.
enum FastVaultPresence: Equatable, Sendable {
    case present
    case absent
    case unknown(Failure)

    enum Failure: Equatable, Sendable {
        case cancelled
        case requestFailed
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// The cache and any in-flight response belong to this exact signer topology.
struct FastVaultTopology: Equatable {
    let publicKey: String
    let localParty: String
    let signers: [String]

    init(_ vault: Vault) {
        publicKey = vault.pubKeyECDSA
        localParty = vault.localPartyID
        signers = vault.signers
    }
}
