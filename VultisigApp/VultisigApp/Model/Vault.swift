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
    @Attribute(.unique) var publicKeyMLDSA44: String? = nil
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
    /// Deprecated: legacy per-vault promo-banner dismissals. Superseded by the
    /// app-wide `PromoBannerDismissalStore`; read only once at launch by
    /// `PromoBannerDismissalMigration`. Kept in the schema to avoid a SwiftData
    /// migration; remove behind a versioned schema stage in a later release.
    var closedBanners: [String] = []
    var defiChains: [Chain] = []
    /// Yield providers the user enabled in the DeFi tab, stored as raw
    /// `DefiYieldProviderID` values so adding a provider needs no new column.
    /// Use `isDefiProviderEnabled(_:)` / `setDefiProvider(_:enabled:)`.
    var enabledDefiProviders: [String] = []
    /// Set once `enabledDefiProviders` has been backfilled from the legacy flags.
    var didMigrateDefiProviders: Bool = false
    // Legacy per-provider toggle — superseded by `enabledDefiProviders`; retained
    // as the migration source and for backup back-compat, not read by feature code.
    var isCircleEnabled: Bool = true

    // FastVault eligibility cache — populated by FastVaultEligibilityRefresher on
    // app foreground + vault switch. Reads are sync; refresh happens at planned
    // trigger points rather than per-screen-mount. Local-only state, not part of
    // the schema — repopulated on every cold start by the refresher.
    @Transient var fastVaultEligibility: Bool = false
    @Transient var fastVaultEligibilityCheckedAt: Date? = nil

    @Relationship(deleteRule: .cascade) var coins = [Coin]()
    @Relationship(deleteRule: .cascade) var hiddenTokens = [HiddenToken]()
    @Relationship(deleteRule: .cascade) var referralCode: ReferralCode?
    @Relationship(deleteRule: .cascade) var referredCode: ReferredCode?
    @Relationship(deleteRule: .cascade) var settings: VaultSettings?
    // Visible Defi Positions
    @Relationship(deleteRule: .cascade) var defiPositions: [DefiPositions] = []
    // Defi Positions Data for caching
    @Relationship(deleteRule: .cascade) var bondPositions: [BondPosition] = []
    @Relationship(deleteRule: .cascade) var stakePositions: [StakePosition] = []
    @Relationship(deleteRule: .cascade) var lpPositions: [LPPosition] = []
    @Relationship(deleteRule: .cascade) var circlePosition: CirclePosition?
    @Relationship(deleteRule: .cascade) var limitOrders: [LimitOrder] = []
    // Generalized yield-vault position cache, keyed (providerID, pubKeyECDSA).
    // `circlePosition` is retained for the one-time migration backfill of
    // pre-existing Circle rows; new reads/writes go here.
    @Relationship(deleteRule: .cascade) var yieldPositions: [YieldPosition] = []
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
        case enabledDefiProviders
        case defiPositions
        case activeBondedNodes
        case stakePositions
        case lpPositions
        case publicKeyMLDSA44
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
        if let providers = try container.decodeIfPresent([String].self, forKey: .enabledDefiProviders) {
            enabledDefiProviders = providers
            didMigrateDefiProviders = true
        } else {
            // Legacy backup (pre-array): the flags above drive reads until the
            // one-time backfill runs.
            enabledDefiProviders = []
            didMigrateDefiProviders = false
        }
        defiPositions = try container.decodeIfPresent([DefiPositions].self, forKey: .defiPositions) ?? []
        publicKeyMLDSA44 = try container.decodeIfPresent(String.self, forKey: .publicKeyMLDSA44)
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
        // Encode the effective (post-migration) state under the legacy keys so
        // older app versions importing this backup still read the right toggles.
        try container.encode(isDefiProviderEnabled(.circle), forKey: .isCircleEnabled)
        // Encode the effective provider set, not the raw (possibly-unmigrated,
        // empty) buffer — otherwise importing a pre-backfill backup would decode
        // an empty array as authoritative and drop the legacy-enabled providers.
        try container.encode(currentDefiProviders(), forKey: .enabledDefiProviders)
        try container.encodeIfPresent(defiPositions, forKey: .defiPositions)
        try container.encodeIfPresent(publicKeyMLDSA44, forKey: .publicKeyMLDSA44)
    }

    func setOrder(_ index: Int) {
        order = index
    }

    // MARK: - DeFi yield providers

    /// Whether the user enabled a yield provider in the DeFi tab. Reads the
    /// migrated array, falling back to the legacy flags until the backfill runs.
    func isDefiProviderEnabled(_ id: DefiYieldProviderID) -> Bool {
        currentDefiProviders().contains(id.rawValue)
    }

    /// Enables or disables a yield provider, migrating the legacy flags into the
    /// array on first write.
    func setDefiProvider(_ id: DefiYieldProviderID, enabled: Bool) {
        var providers = currentDefiProviders()
        providers.removeAll { $0 == id.rawValue }
        if enabled {
            providers.append(id.rawValue)
        }
        enabledDefiProviders = providers
        didMigrateDefiProviders = true
    }

    /// One-time backfill of `enabledDefiProviders` from the legacy per-provider
    /// flags. Returns `true` when it performed the migration so the caller can
    /// persist. Idempotent.
    @discardableResult
    func migrateLegacyDefiProvidersIfNeeded() -> Bool {
        guard !didMigrateDefiProviders else { return false }
        enabledDefiProviders = legacyDefiProviders()
        didMigrateDefiProviders = true
        return true
    }

    private func currentDefiProviders() -> [String] {
        didMigrateDefiProviders ? enabledDefiProviders : legacyDefiProviders()
    }

    private func legacyDefiProviders() -> [String] {
        var providers: [String] = []
        if isCircleEnabled { providers.append(DefiYieldProviderID.circle.rawValue) }
        return providers
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

    /// Whether this vault can be signed via the FastVault path. Single
    /// source of truth — readers everywhere route on this. The value is
    /// cached on the model (`fastVaultEligibility` + `fastVaultEligibilityCheckedAt`,
    /// populated by `FastVaultEligibilityRefresher` on vault open + scenePhase
    /// active). Returns `false` until the cache is populated — an extra
    /// paired-sign round trip in that narrow window is preferable to
    /// incorrectly routing a non-eligible vault into the FastVault path
    /// based on the structural `hasServerSigner` alone.
    ///
    /// Never true for the server-side party itself; only the user-side
    /// devices ever route to FastVault signing.
    var isFastVault: Bool {
        guard !localPartyID.lowercased().starts(with: "server-") else { return false }
        guard fastVaultEligibilityCheckedAt != nil else { return false }
        return fastVaultEligibility
    }

    /// Structural-only check: is there a `server-` party in this vault's
    /// signer list (and we're not the server ourselves)? Internal helper —
    /// used by `FastVaultService.isEligibleForFastSign` to compute the
    /// canonical eligibility (`isExist && hasServerSigner`) before writing
    /// the result to the cache. Reading `isFastVault` here would create a
    /// circular dependency on the cached value the refresher is computing.
    var hasServerSigner: Bool {
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
            // KeyImport vaults can only operate on chains whose per-chain TSS
            // keyshares were derived during import. `coins` may temporarily
            // drift if a feature inserts an unauthorized native token, so use
            // `chainPublicKeys` as the authoritative source. Legacy JSON
            // backups predate `chainPublicKeys` persistence — fall back to the
            // coin-derived list so a restored vault stays usable.
            chainPublicKeys.isEmpty ? chains : chainPublicKeys.map(\.chain)
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

    /// The QBTC claim signs its BTC ECDSA round exclusively via DKLS (see
    /// `QBTCClaimRoundRunner`). GG20 keyshares can't take part in that
    /// ceremony — a GG20 vault that tries to claim hangs and fails with a
    /// DKLS "fail to download setup message" error — so the claim flow is
    /// limited to DKLS-family vaults. A nil `libType` is a legacy GG20
    /// vault and is therefore unsupported.
    var supportsQbtcClaim: Bool {
        switch libType {
        case .DKLS, .KeyImport:
            true
        case .GG20, nil:
            false
        }
    }

    func coins(for chain: Chain) -> [Coin] {
        coins.filter { $0.chain == chain }
    }

    func address(for chain: Chain) -> String? {
        coins.first(where: { $0.chain == chain })?.address
    }

    var chainsWithCoins: [Chain] {
        coins.map { $0.chain }.uniqueBy { $0 }
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
