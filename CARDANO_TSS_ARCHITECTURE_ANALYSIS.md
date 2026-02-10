# TSS Architecture Analysis: Supporting Cardano Base Addresses

**Date:** February 4, 2026
**Status:** Investigation Complete
**Question:** Can Vultisig's TSS architecture support multiple keys per chain for Cardano base addresses?

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [The Two-Key Requirement](#the-two-key-requirement)
4. [Architectural Constraints](#architectural-constraints)
5. [Implementation Options](#implementation-options)
6. [Development Effort Estimate](#development-effort-estimate)
7. [Risks & Challenges](#risks--challenges)
8. [Recommendation](#recommendation)

---

## Executive Summary

### Question
Can Vultisig support Cardano base addresses (addr1q) which require TWO keys (spending + staking), or are we constrained to enterprise addresses (addr1v) with ONE key?

### Answer
**YES, but it requires significant architectural refactoring.**

**Current State:**
- ✅ TSS processes **ONE key per chain**
- ✅ Enterprise addresses (addr1v) with **spending key only**
- ✅ Fully functional for payments

**Required for Base Addresses:**
- 🔄 TSS processes **TWO keys for Cardano** (spending + staking)
- 🔄 Data model stores **multiple keys per chain**
- 🔄 Keysign selects **correct key type** (spending vs staking)
- 🔄 Address generation uses **both keys**

**Development Effort:** 2-3 weeks, 15-17 files affected

**Risk Level:** Medium - Complex but feasible

---

## Current Architecture Analysis

### 1. Data Model: ONE Key Per Chain

```swift
// Vault.swift - Lines 40
@Relationship(deleteRule: .cascade) var chainPublicKeys: [ChainPublicKey] = []

// ChainPublicKey.swift
@Model
final class ChainPublicKey {
    @Attribute(.unique) var id: String
    var chain: Chain
    var publicKeyHex: String  // ONE public key
    var isEddsa: Bool
}

// KeyShare.swift
class KeyShare: Codable {
    let pubkey: String
    let keyshare: String  // ONE encrypted share
}
```

**Architecture:**
- Vault has ONE array of `ChainPublicKey`
- Each `ChainPublicKey` has ONE `publicKeyHex`
- Each `KeyShare` stores ONE encrypted share
- **Constraint:** ONE public key per chain

### 2. TSS Ceremony: ONE Per Key

```swift
// KeygenViewModel.swift - Lines 235-275
for chain in chains {
    var chainKey: Data?
    if isInitiateDevice {
        chainKey = getChainKey(for: chain, wallet: wallet)  // ONE key from WalletCore
    }

    let keyshare: DKLSKeyshare
    if chain.isECDSA {
        keyshare = try await importDklsKey(ecdsaPrivateKeyHex: chainKey?.hexString, chain: chain)
    } else {
        // EdDSA (Cardano, Solana, etc.)
        var chainSeed: Data?
        if isInitiateDevice {
            guard let chainKey,
                  let serializedChainSeed = Data.clampThenUniformScalar(from: chainKey) else {
                throw HelperError.runtimeError("Couldn't transform key")
            }
            chainSeed = serializedChainSeed
        }

        keyshare = try await importSchnorrKey(eddsaPrivateKeyHex: chainSeed?.hexString, chain: chain)
    }

    // Store ONE keyshare per chain
    vault.keyshares.append(KeyShare(pubkey: keyshare.PubKey, keyshare: keyshare.Keyshare))

    // Store ONE public key per chain
    vault.chainPublicKeys.append(
        ChainPublicKey(chain: chain, publicKeyHex: keyshare.PubKey, isEddsa: !chain.isECDSA)
    )
}
```

**Process:**
1. Get ONE private key from WalletCore
2. Run ONE TSS ceremony (DKLS or Schnorr)
3. Get back ONE keyshare
4. Store ONE public key + ONE keyshare

**Time per chain:** ~10-30 seconds

### 3. Keysign: Lookup ONE Key

```swift
// KeysignViewModel.swift - Lines 174-175
publicKey = self.vault.chainPublicKeys.first(where: {
    $0.chain == keysignPayload.coin.chain
})?.publicKeyHex
```

**Assumption:** Exactly ONE public key per chain for signing.

### 4. Address Generation: Uses ONE Key

```swift
// CoinFactory.swift - Cardano case
case .cardano:
    address = try createCardanoEnterpriseAddress(spendingKeyHex: publicKeyEdDSA)
```

```swift
// CoinFactory+Cardano.swift - Lines 49-69
static func createCardanoEnterpriseAddress(spendingKeyHex: String) throws -> String {
    let hash = Hash.blake2b(data: spendingKeyData, size: 28)

    var addressData = Data()
    addressData.append(0x61)  // Enterprise: (6 << 4) + 1
    addressData.append(hash)

    return Bech32.encode(hrp: "addr", data: addressData)
}
```

**Result:** `addr1v...` (29 bytes) - Payment hash only

---

## The Two-Key Requirement

### Cardano Address Types

| Type | Prefix | Structure | Keys Required |
|------|--------|-----------|---------------|
| **Enterprise** | addr1v | `[header:1][payment:28]` = 29 bytes | 1 (spending) |
| **Base** | addr1q | `[header:1][payment:28][staking:28]` = 57 bytes | 2 (spending + staking) |

### Why Two Keys?

**Base addresses (addr1q) enable:**
- ✅ Direct staking from address
- ✅ Delegation to stake pools
- ✅ Earning staking rewards
- ✅ Industry standard format (Trust Wallet, Lace, Yoroi)

**Enterprise addresses (addr1v) limitation:**
- ✅ Full payment functionality
- ❌ No direct staking capability
- ⚠️ Different from other wallets

### WalletCore Provides Both Keys

```
WalletCore's 192-byte Cardano Extended Key:

Bytes 0-31:    Spending key scalar (private key)
Bytes 32-63:   IV for signing with spending key
Bytes 64-95:   Chain code for spending key derivation
Bytes 96-127:  Spending public key (derived from scalar)
Bytes 128-159: Staking key scalar (private key)    ← Available but unused!
Bytes 160-191: IV for signing with staking key
```

**Key Insight:** WalletCore provides the staking key, but Vultisig currently only uses the spending key (bytes 0-31).

---

## Architectural Constraints

### Constraint 1: Data Model (ONE key per chain)

**Current:**
```swift
ChainPublicKey {
    chain: Chain
    publicKeyHex: String  // Single field
}
```

**Needed:**
```swift
ChainPublicKey {
    chain: Chain
    publicKeyHex: String           // Spending key
    secondaryPublicKeyHex: String? // Staking key
    keyType: KeyType?              // .spending or .staking
}
```

**Impact:** Backward compatibility required (optional fields)

### Constraint 2: TSS Ceremony (ONE per iteration)

**Current:** 1 chain = 1 TSS ceremony

**Needed for Cardano:** 1 chain = 2 TSS ceremonies

```swift
// Proposed implementation
if chain == .cardano {
    let cardanoExtendedKey = getChainKey(for: chain, wallet: wallet)

    // CEREMONY 1: Spending key (bytes 0-31)
    let spendingKey = cardanoExtendedKey.prefix(32)
    let spendingKeyshare = try await importSchnorrKey(
        eddsaPrivateKeyHex: spendingKey.hexString,
        chain: .cardano
    )

    // CEREMONY 2: Staking key (bytes 128-159)
    let stakingKey = cardanoExtendedKey.subdata(in: 128..<160)
    let stakingKeyshare = try await importSchnorrKey(
        eddsaPrivateKeyHex: stakingKey.hexString,
        chain: .cardano
    )

    // Store TWO keyshares
    vault.keyshares.append(KeyShare(pubkey: spendingKeyshare.PubKey, ...))
    vault.keyshares.append(KeyShare(pubkey: stakingKeyshare.PubKey, ...))
}
```

**Performance Impact:**
- Current: ~10-30 seconds per chain
- Cardano with 2 keys: ~20-60 seconds
- **Vault creation time increases by 10-30 seconds**

### Constraint 3: Keysign Logic (Assumes ONE key)

**Current:**
```swift
publicKey = vault.chainPublicKeys.first(where: { $0.chain == .cardano })?.publicKeyHex
```

**Needed:**
```swift
// For payment transactions - use spending key
publicKey = vault.chainPublicKeys.first(where: {
    $0.chain == .cardano && $0.keyType == .spending
})?.publicKeyHex

// For staking certificates - use staking key (future)
publicKey = vault.chainPublicKeys.first(where: {
    $0.chain == .cardano && $0.keyType == .staking
})?.publicKeyHex
```

**Note:** Payment transactions only use spending key. Staking key is for delegation/withdrawal certificates.

### Constraint 4: Multiple Files Assume ONE Key

**Files that query by chain:**
```bash
# Grep found 20+ files using this pattern:
chainPublicKeys.first(where: { $0.chain == chain })
```

**Files:**
- KeysignViewModel.swift
- SwapCryptoViewModel.swift
- DefiMainViewModel.swift
- CoinService.swift
- VaultDefaultCoinService.swift
- And 15+ more...

**Impact:** If we store multiple entries per chain (Option B), ALL these files need updates.

---

## Implementation Options

### Option A: Extend ChainPublicKey (⭐ Recommended)

```swift
@Model
final class ChainPublicKey {
    @Attribute(.unique) var id: String
    var chain: Chain
    var publicKeyHex: String           // Primary key (spending)
    var secondaryPublicKeyHex: String? // Optional staking key
    var keyType: KeyType?              // Enum: .spending, .staking, .default
    var isEddsa: Bool
}

enum KeyType: String, Codable {
    case spending
    case staking
    case `default`  // For single-key chains
}
```

**Pros:**
- ✅ Minimal schema changes
- ✅ Backward compatible (optional fields)
- ✅ Clear semantic meaning
- ✅ Works for 99% of multi-key scenarios

**Cons:**
- ⚠️ Limited to 2 keys per chain
- ⚠️ Slightly awkward for future chains needing 3+ keys

**Estimated Effort:** 2 weeks, ~15 files

**Files to Modify:**
1. `ChainPublicKey.swift` - Add secondary key field
2. `Vault.swift` - Migration detection
3. `KeygenViewModel.swift` - 2x ceremony loop
4. `DataExtension.swift` - Key extraction (bytes 128-159)
5. `KeysignViewModel.swift` - Key type selection
6. `CoinFactory.swift` - Use both keys
7. `CoinFactory+Cardano.swift` - Add base address function
8. `VaultDefaultCoinService.swift` - Handle both keys
9. `CoinService.swift` - Handle both keys
10-17. UI/migration files

---

### Option B: Multiple ChainPublicKey Entries

```swift
// Store two separate entries for Cardano
vault.chainPublicKeys.append(
    ChainPublicKey(chain: .cardano, publicKeyHex: spendingKey, keyType: .spending, isEddsa: true)
)
vault.chainPublicKeys.append(
    ChainPublicKey(chain: .cardano, publicKeyHex: stakingKey, keyType: .staking, isEddsa: true)
)
```

**Pros:**
- ✅ Fully flexible (N keys per chain)
- ✅ Future-proof
- ✅ Clean separation of concerns

**Cons:**
- ❌ Breaks assumption of one entry per chain
- ❌ Requires updating ALL 20+ files that query by chain
- ❌ More complex querying logic

**Estimated Effort:** 3 weeks, ~25+ files

---

### Option C: Cardano-Specific Model

```swift
@Model
final class CardanoKeys {
    var spendingKeyHex: String
    var stakingKeyHex: String
}

// Add to Vault
@Relationship(deleteRule: .cascade) var cardanoKeys: CardanoKeys?
```

**Pros:**
- ✅ No impact on other chains
- ✅ Type-safe for Cardano

**Cons:**
- ❌ Special-casing one chain (technical debt)
- ❌ Not extensible to other multi-key chains
- ❌ Inconsistent data access patterns

**Estimated Effort:** 1.5 weeks, ~10 files

---

## Development Effort Estimate

### Recommended: Option A (Extend ChainPublicKey)

| Task | Files | Time |
|------|-------|------|
| **1. Data Model Changes** | | |
| - Update `ChainPublicKey.swift` | 1 | 0.5 day |
| - Add `KeyType` enum | 1 | 0.25 day |
| - Vault migration logic | 1 | 0.25 day |
| **2. Key Extraction** | | |
| - Extract spending key (bytes 0-31) | 1 | 0.5 day |
| - Extract staking key (bytes 128-159) | 1 | 0.5 day |
| - Update `getChainKey()` | 1 | 0.5 day |
| **3. TSS Ceremonies** | | |
| - Modify keygen for 2x Cardano ceremonies | 1 | 1 day |
| - Store 2 keyshares | 1 | 0.5 day |
| - Store 2 public keys | 1 | 0.5 day |
| **4. Keysign Process** | | |
| - Update key lookup | 3 | 1 day |
| - Handle key type selection | 3 | 1 day |
| **5. Address Generation** | | |
| - Implement base address function | 1 | 0.5 day |
| - Update CoinFactory | 1 | 0.5 day |
| **6. Migration** | | |
| - Detection logic | 1 | 0.5 day |
| - UI migration banner | 2 | 1 day |
| - Seed re-import flow | 2 | 1 day |
| **7. Testing** | | |
| - Unit tests | - | 1 day |
| - Integration tests | - | 1 day |
| - E2E tests | - | 1 day |
| - Migration tests | - | 0.5 day |
| **Total** | **~17 files** | **12-14 days** |

**Estimated Effort:** 2-3 weeks

---

## Risks & Challenges

### Risk 1: TSS Ceremony Failures

**Issue:** Running 2 ceremonies doubles the chance of failure (network, timeout, device issues)

**Impact:** User frustration, incomplete vault creation

**Mitigation:**
- ✅ Implement retry logic per ceremony
- ✅ Save progress after each successful ceremony
- ✅ Allow resuming if one ceremony succeeds
- ✅ Clear error messages per ceremony

**Example:**
```
✅ Spending key ceremony successful
❌ Staking key ceremony failed - retrying...
```

### Risk 2: User Confusion (Different Balances)

**Issue:** Even after fixing double SHA512, users will still see different balances if importing same seed to different wallets.

**Current State (after SHA512 fix):**
```
Trust Wallet:  addr1q...xyz → 100 ADA (base address)
Vultisig:      addr1v...abc →   0 ADA (enterprise address, different!)
```

**After Base Address Support:**
```
Trust Wallet:  addr1q...xyz → 100 ADA (base address)
Vultisig:      addr1q...xyz → 100 ADA ✅ (same address, same balance!)
```

**Mitigation:**
- ✅ Clear documentation
- ✅ In-app explainer during import
- ✅ Migration guide with screenshots

### Risk 3: Backward Compatibility

**Issue:** Old vaults have 1 key, new vaults have 2 keys

**Scenarios:**
```
Old Vault (Enterprise):
- chainPublicKeys: [ChainPublicKey(chain: .cardano, publicKeyHex: spending, secondary: nil)]
- Address: addr1v...

New Vault (Base):
- chainPublicKeys: [ChainPublicKey(chain: .cardano, publicKeyHex: spending, secondary: staking)]
- Address: addr1q...
```

**Mitigation:**
- ✅ Use optional fields (`secondaryPublicKeyHex?`)
- ✅ Graceful fallback: if no staking key → use enterprise address
- ✅ Version tracking: `cardanoKeyVersion` field
- ✅ Detection: `needsCardanoBaseAddressMigration` flag

### Risk 4: Migration Complexity

**Issue:** Cannot generate new keys from existing vault

**Why:** TSS vaults store encrypted key shares, NOT the original seed phrase.

**Options:**
1. **Non-Destructive:** Keep enterprise addresses for old vaults
2. **Opt-In:** User re-imports seed phrase to add staking key
3. **Manual Transfer:** User manually transfers funds to new address

**Recommended:** Option 2 (Opt-In with seed re-import)

**UI Flow:**
```
1. Detect old vault → Show banner "Upgrade to Base Address"
2. User taps "Upgrade"
3. "Re-enter seed phrase to add staking capability"
4. Re-run keygen with 2 ceremonies
5. Success: "New base address: addr1q..."
6. Warning: "Your old enterprise address (addr1v...) still has funds. Transfer them manually."
```

### Risk 5: Testing Complexity

**Test Matrix:**
- Old vault (enterprise) → stays enterprise
- New vault (base) → uses base
- Migrated vault → both addresses work
- Transaction signing (spending key)
- Staking certificate signing (staking key)
- Multiple devices (keygen coordination)
- Failure scenarios (partial keygen)

**Estimated Testing Time:** 3-4 days

---

## Recommendation

### Technical Assessment

Supporting Cardano base addresses (2 keys per chain) **IS FEASIBLE** with moderate complexity:

✅ **Feasible:**
- Data model can be extended
- TSS ceremonies can be duplicated
- Keysign logic can select key type
- Address generation can use both keys

⚠️ **Moderate Complexity:**
- 2-3 weeks development time
- 15-17 files affected
- Performance impact (2x ceremony time)
- Migration strategy needed

❌ **Challenges:**
- User confusion risk
- Backward compatibility
- Testing complexity

### Recommended Approach

**Ship in Two Phases:**

#### Phase 1: Fix Double SHA512 (Ship Now)
- ✅ Implement `cardanoClampedScalar()` function
- ✅ Fix key derivation (no double hashing)
- ✅ Keep enterprise addresses (addr1v)
- ✅ Fully functional for payments
- ⚠️ Still different from Trust Wallet (different address format)

**Effort:** 2-3 days
**Risk:** Low
**User Impact:** Cardano works correctly, but different address format

---

#### Phase 2: Base Address Support (Future Enhancement)
- 🔄 Implement Option A (Extend ChainPublicKey)
- 🔄 Add 2x TSS ceremonies for Cardano
- 🔄 Implement base address generation
- 🔄 Add migration UI for existing vaults
- ✅ True compatibility with Trust Wallet/Lace/Yoroi

**Effort:** 2-3 weeks
**Risk:** Medium
**User Impact:** Same addresses as other wallets, staking capability

### Rationale for Two-Phase Approach

**Why Phase 1 First:**
- ✅ Unblocks Cardano support immediately
- ✅ Enterprise addresses are fully functional
- ✅ Lower risk (simpler change)
- ✅ Can gather user feedback on staking demand
- ✅ Time for thorough testing of multi-key architecture

**Why Phase 2 Later:**
- ⏰ Requires significant development time
- ⚠️ Higher complexity/risk
- 📊 Can assess user demand for staking first
- 🧪 More testing required
- 📋 Roadmap item based on user feedback

### Decision Tree

```
Do users NEED Trust Wallet compatibility?
├─ CRITICAL → Implement Phase 2 immediately
└─ NICE TO HAVE → Ship Phase 1, roadmap Phase 2

Do users NEED on-chain staking?
├─ CRITICAL → Implement Phase 2 immediately
└─ NICE TO HAVE → Ship Phase 1, roadmap Phase 2

Are development resources available (2-3 weeks)?
├─ YES → Consider Phase 2 alongside Phase 1
└─ NO → Ship Phase 1, plan Phase 2 for later sprint
```

### User Communication

**Phase 1 Message:**
```
"Vultisig now supports Cardano with Enterprise addresses (addr1v)
for secure payments. Base address support (addr1q) with staking
capabilities is coming in a future update."
```

**Phase 2 Message:**
```
"Vultisig now supports Cardano Base addresses (addr1q), providing
full compatibility with Trust Wallet, Lace, and Yoroi. Existing
vaults can be upgraded by re-importing your seed phrase."
```

---

## Conclusion

### Summary

**Can Vultisig support Cardano base addresses with TSS?**

**YES**, but with caveats:

1. ✅ **Technically Feasible**
   - Data model can be extended
   - TSS can run multiple ceremonies
   - Architecture supports it

2. ⚠️ **Requires Significant Work**
   - 2-3 weeks development
   - 15-17 files affected
   - Testing complexity

3. ⚠️ **User Impact Considerations**
   - Different addresses = different balances (confusing)
   - Migration requires seed re-import
   - Increased vault creation time

4. ✅ **Recommended Approach**
   - **Phase 1:** Fix SHA512, ship enterprise addresses (addr1v)
   - **Phase 2:** Add base address support (addr1q) as enhancement

### Final Recommendation

**Ship Phase 1 first (enterprise addresses), implement Phase 2 based on user demand and resource availability.**

This approach:
- ✅ Unblocks Cardano support immediately
- ✅ Provides fully functional payment capability
- ✅ Reduces risk of rushing complex TSS changes
- ✅ Allows time for proper testing and migration UX
- ✅ Can gather user feedback before major architectural changes

**Bottom Line:** Enterprise addresses (addr1v) work perfectly for payments. Base addresses (addr1q) are nice-to-have for staking and compatibility, but not required for core functionality.

---

**Document Version:** 1.0
**Last Updated:** February 4, 2026
**Authors:** Vultisig Development Team
