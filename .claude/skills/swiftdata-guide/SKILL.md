---
name: swiftdata-guide
description: SwiftData models, Storage API, concurrency patterns, and three-phase architecture.
user-invocable: false
---

# SwiftData Guide

**CRITICAL:** SwiftData models (`@Model` classes) have strict thread affinity requirements and MUST be accessed only from MainActor. Violating this causes crashes with `NSManagedObjectContext` errors.

## Core Rules

1. **Never access SwiftData models from non-MainActor contexts**
2. **Never capture SwiftData models in concurrent tasks or closures**
3. **Use value types (structs) to pass data across actor boundaries**
4. **Batch updates with a single `Storage.shared.save()` call**
5. **Mark functions that work with SwiftData models as `@MainActor`**

---

## All @Model Classes (14 total)

### Vault (root entity)

**File:** `Model/Vault.swift`

```swift
@Model final class Vault: ObservableObject, Codable {
    @Attribute(.unique) var name: String
    @Attribute(.unique) var pubKeyECDSA: String
    @Attribute(.unique) var pubKeyEdDSA: String
    var publicKeyMLDSA44: String?
    var signers: [String]
    var localPartyID: String
    var keyshares: [KeyShare]
    var hexChainCode: String
    var resharePrefix: String?
    var libType: LibType?             // .GG20, .DKLS, .KeyImport
    var createdAt: Date
    var order: Int
    var isBackedUp: Bool
    var closedBanners: [String]
    var defiChains: [Chain]

    // Cascade-delete relationships
    @Relationship(deleteRule: .cascade) var coins: [Coin]
    @Relationship(deleteRule: .cascade) var hiddenTokens: [HiddenToken]
    @Relationship(deleteRule: .cascade) var referralCode: ReferralCode?
    @Relationship(deleteRule: .cascade) var referredCode: ReferredCode?
    @Relationship(deleteRule: .cascade) var defiPositions: [DefiPositions]
    @Relationship(deleteRule: .cascade) var bondPositions: [BondPosition]
    @Relationship(deleteRule: .cascade) var stakePositions: [StakePosition]
    @Relationship(deleteRule: .cascade) var lpPositions: [LPPosition]
    @Relationship(deleteRule: .cascade) var chainPublicKeys: [ChainPublicKey]
}
```

### Coin

**File:** `Model/Coin.swift`

```swift
@Model class Coin: ObservableObject, Codable, Hashable {
    var id: String
    var chain: Chain
    var address: String
    var hexPublicKey: String
    var ticker: String
    var contractAddress: String
    var isNativeToken: Bool
    var strDecimals: String        // stored as string, accessed as Int
    var logo: String
    var priceProviderId: String
    var rawBalance: String
    var stakedBalance: String
    @Transient var bondedNodes: [RuneBondNode]  // not persisted

    @Relationship(inverse: \Vault.coins) var vault: Vault?
}
```

### Folder

**File:** `Model/Folder.swift`

```swift
@Model class Folder: Hashable, Equatable {
    var id: UUID
    var folderName: String
    var containedVaultNames: [String]
    var order: Int
}
```

### ChainPublicKey

**File:** `Model/ChainPublicKey.swift`

```swift
@Model final class ChainPublicKey {
    @Attribute(.unique) var id: String    // "{chain.name}-{publicKeyHex}"
    var chain: Chain
    var publicKeyHex: String
    var isEddsa: Bool

    @Relationship(inverse: \Vault.chainPublicKeys) var vault: Vault?
}
```

### StoredPendingTransaction

**File:** `Model/PendingTransaction.swift`

```swift
@Model final class StoredPendingTransaction {
    @Attribute(.unique) var txHash: String
    var chain: Chain
    var status: String           // "broadcasted", "pending", "confirmed", "failed", "timeout"
    var createdAt: Date
    var lastCheckedAt: Date?
    var confirmedAt: Date?
    var failureReason: String?
    var estimatedTime: String
    var coinTicker: String?
    var amount: String?
    var toAddress: String?
}
```

### HiddenToken

**File:** `Model/HiddenToken.swift`

```swift
@Model class HiddenToken: Hashable {
    var chain: String
    var ticker: String
    var contractAddress: String
    var hiddenAt: Date

    @Relationship(inverse: \Vault.hiddenTokens) var vault: Vault?
}
```

### DefiPositions

**File:** `Model/DefiPositions.swift`

```swift
@Model final class DefiPositions: Codable {
    var chain: Chain
    var bonds: [CoinMeta]
    var staking: [CoinMeta]
    var lps: [CoinMeta]

    @Relationship(inverse: \Vault.defiPositions) var vault: Vault?
}
```

### BondPosition

**File:** `Features/Defi/DefiChain/Model/BondPosition.swift`

```swift
@Model final class BondPosition {
    @Attribute(.unique) var id: String    // "{chain.ticker}_{contractAddress}_{nodeAddress}_{vaultPubKey}"
    var node: BondNode
    var amount: Decimal
    var apy: Double
    var nextReward: Decimal
    var nextChurn: Date?

    @Relationship(inverse: \Vault.bondPositions) var vault: Vault?
}
```

### LPPosition

**File:** `Features/Defi/DefiChain/Model/LPPosition.swift`

```swift
@Model final class LPPosition {
    @Attribute(.unique) var id: String
    var coin1: CoinMeta
    var coin1Amount: Decimal
    var coin2: CoinMeta
    var coin2Amount: Decimal
    var poolName: String?
    var apr: Double
    var lastUpdated: Date

    @Relationship(inverse: \Vault.lpPositions) var vault: Vault?
}
```

### StakePosition

**File:** `Features/Defi/DefiChain/Model/Staking/StakePosition.swift`

```swift
@Model final class StakePosition {
    @Attribute(.unique) var id: String
    var coin: CoinMeta
    var type: StakePositionType     // .stake, .compound, .index
    var amount: Decimal
    var availableToUnstake: Decimal?
    var apr: Double?
    var estimatedReward: Decimal?
    var rewards: Decimal?
    var rewardCoin: CoinMeta?

    @Relationship(inverse: \Vault.stakePositions) var vault: Vault?
}
```

### ReferralCode / ReferredCode

**Files:** `Model/ReferralCode.swift`, `Model/ReferredCode.swift`

```swift
@Model final class ReferralCode: ObservableObject {
    @Attribute(.unique) var id: UUID
    var code: String
    var createdAt: Date
    @Relationship(inverse: \Vault.referralCode) var vault: Vault?
}

@Model final class ReferredCode: ObservableObject {
    @Attribute(.unique) var id: UUID
    var code: String
    var createdAt: Date
    @Relationship(inverse: \Vault.referredCode) var vault: Vault?
}
```

### AddressBookItem

**File:** `Model/AddressBookItem.swift`

```swift
@Model class AddressBookItem: Equatable {
    var id: UUID
    var title: String
    var address: String
    var coinMeta: CoinMeta
    var order: Int
}
```

### DatabaseRate

**File:** `Services/Rates/DatabaseRate.swift`

```swift
@Model final class DatabaseRate {
    @Attribute(.unique) var id: String
    var fiat: String
    var crypto: String
    var value: Double
}
```

---

## Storage Singleton

**File:** `Services/Storage/Storage.swift`

```swift
final class Storage {
    static let shared = Storage()
    var modelContext: ModelContext!

    @MainActor func save() throws
    @MainActor func insert<T>(_ model: T) where T: PersistentModel
    @MainActor func insert<T>(_ models: [T]) where T: PersistentModel
    @MainActor func delete<T>(_ model: T) where T: PersistentModel
}
```

All operations are `@MainActor`. Always call `save()` after modifications.

---

## Anti-Pattern: Direct Model Access in Concurrent Code

```swift
// WRONG - causes crashes
func updateBalances(vault: Vault) async {
    await withTaskGroup(of: Void.self) { group in
        for coin in vault.coins {              // accessing SwiftData off MainActor
            group.addTask {
                let balance = try await fetchBalance(for: coin)  // capturing model
                coin.balance = balance         // modifying off MainActor
            }
        }
    }
}
```

---

## Correct Pattern: Three-Phase Architecture

### Setup: Define value types

```swift
private struct CoinIdentifier: Hashable {
    let coinId: String
    let coinMeta: CoinMeta
    let address: String

    init(from coin: Coin) {
        self.coinId = coin.id
        self.coinMeta = coin.toCoinMeta()
        self.address = coin.address
    }
}

private struct CoinBalanceUpdate {
    let coinId: String
    let rawBalance: String?
    let error: Error?
}
```

### Phase 1: Extract on MainActor

```swift
@MainActor
private func extractCoinIdentifiers(from vault: Vault) -> [CoinIdentifier] {
    vault.coins.map { CoinIdentifier(from: $0) }
}
```

### Phase 2: Fetch concurrently (value types only)

```swift
private func fetchUpdates(for identifiers: [CoinIdentifier]) async -> [CoinBalanceUpdate] {
    await withTaskGroup(of: CoinBalanceUpdate.self) { group in
        var updates: [CoinBalanceUpdate] = []
        for id in identifiers {
            group.addTask {
                do {
                    let balance = try await self.fetchBalance(for: id.coinMeta, address: id.address)
                    return CoinBalanceUpdate(coinId: id.coinId, rawBalance: balance, error: nil)
                } catch {
                    return CoinBalanceUpdate(coinId: id.coinId, rawBalance: nil, error: error)
                }
            }
        }
        for await update in group { updates.append(update) }
        return updates
    }
}
```

### Phase 3: Apply on MainActor in batch

```swift
@MainActor
private func applyUpdates(_ updates: [CoinBalanceUpdate], to vault: Vault) throws {
    let coinsByID = Dictionary(uniqueKeysWithValues: vault.coins.map { ($0.id, $0) })
    for update in updates {
        guard let coin = coinsByID[update.coinId] else { continue }
        if let balance = update.rawBalance { coin.rawBalance = balance }
    }
    try Storage.shared.save()  // Single save
}
```

### Usage: Orchestrate

```swift
func updateBalances(vault: Vault) async {
    let identifiers = await extractCoinIdentifiers(from: vault)
    let updates = await fetchUpdates(for: identifiers)
    try await applyUpdates(updates, to: vault)
}
```

**Reference:** `Services/BalanceService.swift`

---

## Swift 6 Sendable Compliance

Mark entire function as `@MainActor` instead of capturing models in closures:

```swift
// WRONG
func updateBalance(for coin: Coin) async {
    let id = await MainActor.run { CoinIdentifier(from: coin) }  // capturing coin
}

// CORRECT
@MainActor
func updateBalance(for coin: Coin) async {
    let id = CoinIdentifier(from: coin)             // already on MainActor
    let update = await fetchBalanceUpdate(for: id)   // await hops off MainActor
    coin.rawBalance = update.rawBalance              // back on MainActor
    try Storage.shared.save()
}
```

---

## Batch Upsert Pattern

**Reference:** `Features/Defi/Common/Service/DefiPositionsStorageService.swift`

```swift
@MainActor
func upsert(_ positions: [LPPosition]) throws {
    let ids = positions.map { $0.id }
    let descriptor = FetchDescriptor<LPPosition>(
        predicate: #Predicate<LPPosition> { ids.contains($0.id) }
    )
    let existing = try Storage.shared.modelContext.fetch(descriptor)
    let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

    for position in positions {
        if let existing = existingByID[position.id] {
            existing.coin1Amount = position.coin1Amount  // update
            existing.apr = position.apr
        } else {
            Storage.shared.modelContext.insert(position)  // insert
        }
    }
    try Storage.shared.save()  // Single save
}
```

---

## Checklist

Before writing code that works with SwiftData models:

- [ ] Function marked `@MainActor` if it accesses models directly?
- [ ] Value types used to pass data across actor boundaries?
- [ ] Models extracted on MainActor before concurrent work?
- [ ] Updates applied on MainActor after concurrent work?
- [ ] Single `save()` call per batch operation?
- [ ] Models never captured in concurrent tasks?
- [ ] No Swift 6 Sendable warnings?
