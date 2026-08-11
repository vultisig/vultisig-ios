//
//  SyntheticVaultSeeder.swift
//  VultisigApp
//
//  DEBUG-ONLY investigation scaffold. Seeds a fully synthetic vault into the
//  SwiftData store so the wallet home screen renders on a machine that has no
//  real vault — which is the standing blocker on reproducing the macOS layout
//  loop (see the #4470 recurrence investigation).
//
//  TWO LOCKS, deliberately:
//    1. `#if DEBUG` — never compiled into a Release build.
//    2. `-seedSyntheticVault` launch argument — never fires on an ordinary
//       debug run, only when explicitly asked for.
//
//  It writes ONLY to SwiftData. No keychain, no network, no real key shares,
//  no real addresses. `keyshares` is left empty on purpose: this vault exists
//  to make views lay out, not to sign anything, and an empty keyshare list
//  keeps it structurally incapable of being mistaken for a usable wallet.
//
//  REMOVE IT AGAIN with `-removeSyntheticVault` (deletes by pubKeyECDSA and
//  nothing else), or delete the whole container:
//    rm -rf ~/Library/Containers/com.vultisig.wallet
//

#if DEBUG
import Foundation
import SwiftData

enum SyntheticVaultSeeder {
    /// Marker that identifies everything this seeder created. Nothing else in
    /// the app can produce this value, so removal is exact.
    static let syntheticPubKeyECDSA = "SYNTHETIC-REPRO-VAULT-DO-NOT-SIGN"
    private static let syntheticName = "Synthetic Repro Vault"

    static var isSeedRequested: Bool {
        CommandLine.arguments.contains("-seedSyntheticVault")
    }

    static var isRemovalRequested: Bool {
        CommandLine.arguments.contains("-removeSyntheticVault")
    }

    @MainActor
    static func runIfRequested() {
        if isRemovalRequested { remove(); return }
        guard isSeedRequested else { return }
        seed()
    }

    // MARK: - Seed

    @MainActor
    private static func seed() {
        let context = Storage.shared.modelContext!

        if let existing = fetchSynthetic(in: context) {
            note("synthetic vault already present (\(existing.coins.count) coins) — leaving it alone")
            return
        }

        let vault = Vault(name: syntheticName, libType: .DKLS)
        vault.pubKeyECDSA = syntheticPubKeyECDSA
        vault.pubKeyEdDSA = "SYNTHETIC-EDDSA"
        vault.hexChainCode = String(repeating: "ab", count: 32)
        vault.localPartyID = "synthetic-mac"
        vault.signers = ["synthetic-mac", "synthetic-peer"]
        vault.isBackedUp = true          // suppresses the backup banner/nag
        vault.keyshares = []             // deliberately empty — cannot sign
        context.insert(vault)

        // Native coins across several chains, including the DeFi-capable ones,
        // so the chain list, the balance header and the DeFi tab all populate.
        for meta in nativeMetas() {
            let coin = Coin(
                asset: meta,
                address: syntheticAddress(for: meta),
                hexPublicKey: String(repeating: "cd", count: 33)
            )
            coin.rawBalance = syntheticRawBalance(for: meta)
            coin.vault = vault
            context.insert(coin)
        }

        // DeFi rows. These are the @Model types under suspicion elsewhere, so
        // the repro needs them to actually exist rather than be implied.
        seedDefiPositions(vault: vault, context: context)

        do {
            try context.save()
            // Make the app select it directly on the next launch instead of
            // opening the vault picker — a returning user, which is what the
            // capture shows (the window was restored, not freshly created).
            UserDefaults.standard.set(syntheticName, forKey: "vaultName")
            UserDefaults.standard.set(syntheticPubKeyECDSA, forKey: "selectedPubKeyECDSA")
            UserDefaults.standard.set(false, forKey: "showOnboarding")
            note("seeded synthetic vault: \(vault.coins.count) coins, "
                 + "\(vault.stakePositions.count) stake, \(vault.lpPositions.count) LP")
        } catch {
            note("SEED FAILED: \(error)")
        }
    }

    @MainActor
    private static func seedDefiPositions(vault: Vault, context: ModelContext) {
        let rune = TokensStore.rune
        let tcy = TokensStore.tcy

        vault.defiChains = [.thorChain]

        let stake = StakePosition(
            coin: tcy,
            type: .stake,
            amount: 1234.5678,
            availableToUnstake: 1234.5678,
            apr: 0.0912,
            estimatedReward: 12.34,
            rewards: 5.67,
            rewardCoin: rune,
            poolName: "TCY Staking",
            vault: vault
        )
        context.insert(stake)

        let lp = LPPosition(
            LPPositionData(
                coin1: rune,
                coin1Amount: 42.5,
                coin2: btcMeta,
                coin2Amount: 0.0125,
                poolName: "BTC.BTC",
                poolUnits: "1234567",
                apr: 0.0731
            ),
            vault: vault
        )
        context.insert(lp)
    }

    // MARK: - Remove

    @MainActor
    static func remove() {
        let context = Storage.shared.modelContext!
        guard let vault = fetchSynthetic(in: context) else {
            note("no synthetic vault to remove")
            return
        }
        // The relationships are `.cascade`, so deleting the vault takes its
        // coins and positions with it.
        context.delete(vault)
        do {
            try context.save()
            UserDefaults.standard.removeObject(forKey: "vaultName")
            UserDefaults.standard.removeObject(forKey: "selectedPubKeyECDSA")
            note("removed synthetic vault")
        } catch {
            note("REMOVE FAILED: \(error)")
        }
    }

    @MainActor
    private static func fetchSynthetic(in context: ModelContext) -> Vault? {
        let key = syntheticPubKeyECDSA
        let descriptor = FetchDescriptor<Vault>(
            predicate: #Predicate { $0.pubKeyECDSA == key }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Fixtures

    private static let btcMeta = CoinMeta(
        chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8,
        priceProviderId: "bitcoin", contractAddress: "", isNativeToken: true
    )

    private static func nativeMetas() -> [CoinMeta] {
        var metas: [CoinMeta] = [btcMeta, TokensStore.rune]
        // Pull the remaining natives out of the bundled store so tickers,
        // logos and decimals are the real ones and the rows render normally.
        let wanted: [Chain] = [.ethereum, .solana, .thorChain, .bitcoin]
        for chain in wanted {
            if let meta = TokensStore.TokenSelectionAssets.first(where: {
                $0.chain == chain && $0.isNativeToken
            }), !metas.contains(where: { $0.chain == meta.chain && $0.ticker == meta.ticker }) {
                metas.append(meta)
            }
        }
        return metas
    }

    /// Deterministic, obviously-fake, and never a valid address on any chain.
    private static func syntheticAddress(for meta: CoinMeta) -> String {
        "synthetic-\(meta.chain.rawValue.lowercased())-\(meta.ticker.lowercased())"
    }

    private static func syntheticRawBalance(for meta: CoinMeta) -> String {
        // A few whole units in the chain's smallest denomination.
        let units = Decimal(sign: .plus, exponent: meta.decimals, significand: 1)
        return NSDecimalNumber(decimal: units * 3).stringValue
    }

    private static func note(_ message: String) {
        FileHandle.standardError.write("[SyntheticVaultSeeder] \(message)\n".data(using: .utf8)!)
    }
}
#endif
