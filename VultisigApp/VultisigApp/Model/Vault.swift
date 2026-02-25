//
//  Vault.swift
//  VultisigApp

import Foundation
import SwiftData
import WalletCore

@Model
final class Vault: ObservableObject, Codable {
    @Attribute(.unique) var name: String
    @Attribute(.unique) var pubKeyECDSA: String = ""
    @Attribute(.unique) var pubKeyEdDSA: String = ""
    var publicKeyMLDSA44: String? = nil
    var circleWalletAddress: String?

    var signers: [String] = []
    var createdAt: Date = Date.now
    var hexChainCode: String = ""
    var keyshares = [KeyShare]()

/// Note: it is important to record the localPartID of the vault, when the vault is created, the local party id has been record as part of it's local keyshare , and keygen committee thus , when user change their device name , or if they lost the original device , and restore the keyshare to a new device , keysign can still work
    var localPartyID: String = ""
    var resharePrefix: String? = nil
    var order: Int = 0
    var isBackedUp: Bool = false
    var libType: LibType? = LibType.GG20
    var closedBanners: [String] = []
    var defiChains: [Chain] = []
    var isCircleEnabled: Bool = true  // Controls Circle visibility in DeFi section

    @Relationship(deleteRule: .cascade) var coins = [Coin]()
    @Relationship(deleteRule: .cascade) var hiddenTokens = [HiddenToken]()
    @Relationship(deleteRule: .cascade) var referralCode: ReferralCode?
    @Relationship(deleteRule: .cascade) var referredCode: ReferredCode?
    // Visible Defi Positions
    @Relationship(deleteRule: .cascade) var defiPositions: [DefiPositions] = []
    // Defi Positions Data for caching
    @Relationship(deleteRule: .cascade) var bondPositions: [BondPosition] = []
    @Relationship(deleteRule: .cascade) var stakePositions: [StakePosition] = []
    @Relationship(deleteRule: .cascade) var lpPositions: [LPPosition] = []
    @Relationship(deleteRule: .cascade) var chainPublicKeys: [ChainPublicKey] = []

    enum CodingKeys: CodingKey {
        case name
        case signers
        case createdAt
        case pubKeyECDSA
        case pubKeyEdDSA
        case hexChainCode
        case keyshares
        case localPartyID
        case resharePrefix
        case circleWalletAddress
        case libType
        case defiChains
        case isCircleEnabled
        case defiPositions
        case activeBondedNodes
        case stakePositions
        case lpPositions
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        signers = try container.decode([String].self, forKey: .signers)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        pubKeyECDSA = try container.decode(String.self, forKey: .pubKeyECDSA)
        pubKeyEdDSA = try container.decode(String.self, forKey: .pubKeyEdDSA)
        hexChainCode = try container.decode(String.self, forKey: .hexChainCode)
        keyshares = try container.decode([KeyShare].self, forKey: .keyshares)
        localPartyID = try container.decode(String.self, forKey: .localPartyID)
        resharePrefix = try container.decodeIfPresent(String.self, forKey: .resharePrefix)
        circleWalletAddress = try container.decodeIfPresent(String.self, forKey: .circleWalletAddress)
        libType = try container.decodeIfPresent(LibType.self, forKey: .libType) ?? .DKLS
        defiChains = try container.decodeIfPresent([Chain].self, forKey: .defiChains) ?? []
        isCircleEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCircleEnabled) ?? true
        defiPositions = try container.decodeIfPresent([DefiPositions].self, forKey: .defiPositions) ?? []
    }

    init(name: String, libType: LibType? = nil) {
        self.name = name
        self.libType = libType ?? .DKLS
    }

    init(
        name: String,
        signers: [String],
        pubKeyECDSA: String,
        pubKeyEdDSA: String,
        keyshares: [KeyShare],
        localPartyID: String,
        hexChainCode: String,
        resharePrefix: String?,
        libType: LibType?
    ) {
        self.name = name
        self.signers = signers
        self.createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
        self.keyshares = keyshares
        self.localPartyID = localPartyID
        self.hexChainCode = hexChainCode
        self.resharePrefix = resharePrefix
        self.libType = libType ?? .DKLS
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(signers, forKey: .signers)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(pubKeyECDSA, forKey: .pubKeyECDSA)
        try container.encode(pubKeyEdDSA, forKey: .pubKeyEdDSA)
        try container.encode(hexChainCode, forKey: .hexChainCode)
        try container.encode(keyshares, forKey: .keyshares)
        try container.encode(localPartyID, forKey: .localPartyID)
        try container.encodeIfPresent(resharePrefix, forKey: .resharePrefix)
        try container.encodeIfPresent(circleWalletAddress, forKey: .circleWalletAddress)
        try container.encodeIfPresent(libType, forKey: .libType)
        try container.encodeIfPresent(defiChains, forKey: .defiChains)
        try container.encodeIfPresent(isCircleEnabled, forKey: .isCircleEnabled)
        try container.encodeIfPresent(defiPositions, forKey: .defiPositions)
    }

    func setOrder(_ index: Int) {
        order = index
    }

    func getThreshold() -> Int {
        let totalSigners = signers.count
        let threshold = Int(ceil(Double(totalSigners) * 2.0 / 3.0)) - 1
        return threshold
    }

    func coin(for meta: CoinMeta) -> Coin? {
        let normalizedTicker = meta.ticker.lowercased()
        let normalizedContract = meta.contractAddress.lowercased()

        return coins.first(where: { coin in
            guard coin.chain == meta.chain else { return false }

            let coinTicker = coin.ticker.lowercased()
            let coinContract = coin.contractAddress.lowercased()

            let isSameContract = normalizedContract == coinContract
            let isSameTicker = coinTicker == normalizedTicker

            // Prefer contract comparison whenever available, fallback to ticker for native tokens
            if normalizedContract.isNotEmpty || coinContract.isNotEmpty {
                return isSameContract
            } else {
                return isSameTicker
            }
        })
    }

    func nativeCoin(for coin: Coin) -> Coin? {
        nativeCoin(for: coin.chain)
    }

    func nativeCoin(for chain: Chain) -> Coin? {
        return coins.first(where: { $0.chain == chain && $0.isNativeToken })
    }

    var isFastVault: Bool {
        if localPartyID.lowercased().starts(with: "server-") {
            return false
        }

        for signer in signers {
            if signer.lowercased().starts(with: "server-") {
                return true
            }
        }

        return false
    }

    var chains: [Chain] {
        coins
            .filter { $0.isNativeToken }
            .map { $0.chain }
            .uniqueBy { $0 }
    }

    var availableChains: [Chain] {
        switch libType {
        case .GG20, .DKLS, nil:
            Chain.allCases
        case .KeyImport:
            chains
        }
    }

    var availableDefiChains: [Chain] {
        CoinAction.defiChains.filter {
            availableChains.contains($0)
        }
    }

    var canCustomizeChains: Bool {
        switch libType {
        case .GG20, .DKLS, nil:
            true
        case .KeyImport:
            false
        }
    }

    func coins(for chain: Chain) -> [Coin] {
        coins.filter { $0.chain == chain }
    }

    func getKeyshare(pubKey: String) -> String? {
        return self.keyshares.first(where: {$0.pubkey == pubKey})?.keyshare
    }

    static func getUniqueVaultName(modelContext: ModelContext, setupType: KeyImportSetupType? = nil) -> String {
        let fetchVaultDescriptor = FetchDescriptor<Vault>()
        do {
            let vaults = try modelContext.fetch(fetchVaultDescriptor)
            let start = vaults.count
            var idx = start
            repeat {
                let vaultName: String?

                if let setupType {
                    let prefix: String
                    switch setupType {
                    case .fast:
                        prefix = "Fast"
                    case .secure:
                        prefix = "Secure"
                    }
                    vaultName = "\(prefix) Vault #\(idx + 1)"
                } else {
                    vaultName = "Vault #\(idx + 1)"
                }

                let vaultExist = vaults.contains { v in
                    v.name == vaultName && !v.pubKeyECDSA.isEmpty
                }

                if !vaultExist {
                    return vaultName ?? ""
                }

                idx += 1
            } while idx < 1000
        } catch {
            print("fail to load all vaults")
        }
        return "Main Vault"
    }

    static let example = Vault(name: "Bitcoin", signers: [], pubKeyECDSA: "ECDSAKey", pubKeyEdDSA: "EdDSAKey", keyshares: [], localPartyID: "partyID", hexChainCode: "hexCode", resharePrefix: nil, libType: .GG20)
    static let fastVaultExample = Vault(name: "server-Bitcoin", signers: [], pubKeyECDSA: "ECDSAKey", pubKeyEdDSA: "EdDSAKey", keyshares: [], localPartyID: "partyID", hexChainCode: "hexCode", resharePrefix: nil, libType: nil)
}

extension Vault {
    var signerPartDescription: String {
        guard let index = signers.firstIndex(of: localPartyID) else {
            return "-"
        }
        let partText = libType == .DKLS ? "shareOf".localized : "partOf".localized
        return String(format: partText, index + 1, signers.count)
    }
}

// MARK: - Coin shortcut extensions

extension Vault {
    var runeCoin: Coin? {
        coins.first(where: { $0.isRune })
    }

    var tcyCoin: Coin? {
        coins.first(where: { $0.chain == .thorChain && $0.ticker.uppercased() == "TCY" })
    }
}
