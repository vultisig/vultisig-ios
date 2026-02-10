# Cardano Key Generation & Address Generation: Wallet Comparison

**Date:** February 4, 2026
**Status:** Analysis Complete
**Purpose:** Compare Vultisig's Cardano implementation with Trust Wallet, Yoroi, and Lace

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Vultisig Status](#current-vultisig-status)
3. [Trust Wallet Implementation](#trust-wallet-implementation)
4. [Yoroi Implementation](#yoroi-implementation)
5. [Lace Implementation](#lace-implementation)
6. [Comparison Matrix](#comparison-matrix)
7. [The Remaining Issue](#the-remaining-issue)
8. [Recommended Next Steps](#recommended-next-steps)

---

## Executive Summary

### The Good News ✅
- All wallets (Trust, Yoroi, Lace) follow **CIP-1852** standard with **Icarus master key generation**
- All use **BIP32-Ed25519** (not standard BIP32) with **PBKDF2-HMAC-SHA512** (4096 iterations)
- All generate **Base addresses (addr1q)** with both spending + staking keys
- The industry standard is well-documented and consistent
- **Vultisig already uses the correct CIP-1852 derivation path** (`m/1852'/1815'/0'/0/0`)

### The Current Issue ⚠️
- **Vultisig** still applies **SHA512 hashing** to Cardano keys (partial fix applied on Feb 2, 2026)
- **Trust/Yoroi/Lace** do NOT apply additional SHA512 because WalletCore already does PBKDF2-HMAC-SHA512
- This causes **payment credentials to differ** between Vultisig and other wallets
- The CARDANO_KEY_FIX.md document describes the full fix, but it hasn't been implemented yet

### The Architectural Difference 🏗️
- **Vultisig** uses **Enterprise addresses (addr1v)** with payment key only
- **Trust/Yoroi/Lace** use **Base addresses (addr1q)** with payment + staking keys
- This is due to Vultisig's TSS architecture (one key per chain, not two)

### 🚨 CRITICAL: Different Addresses = Different Balances

**IMPORTANT USER IMPACT:**

Even after fixing the double SHA512 issue, **different address formats mean different addresses on the blockchain**, which means **DIFFERENT BALANCES**:

```
Same seed phrase in different wallets:

Trust Wallet:  addr1q8hrfv...xyz → Balance: 100 ADA
Vultisig:      addr1v8hrfv...abc → Balance:   0 ADA (different address!)
```

**Why:**
- Enterprise (addr1v) and Base (addr1q) are **different addresses** on the Cardano blockchain
- Different addresses = Different UTXOs = Different transaction histories = Different balances
- "Same payment credential" ≠ "same address"

**User Confusion:**
- ❌ Users cannot import Trust Wallet seed into Vultisig and see their balance
- ❌ Users cannot import Vultisig seed into Trust Wallet and see their balance
- ⚠️ Must manually transfer funds between addresses

**For true compatibility:** Need to implement base address support (significant architectural changes required)

---

## Current Vultisig Status

### What Was Implemented (Feb 2, 2026)

**Commit:** `aac4b455a` - "fix: use clamp key for cardano"

**Changes Made:**
```swift
static func ed25519ClampedScalar(from seed: Data) -> Data? {
    // Handle Cardano's extended key format (192 bytes)
    // Extract the first 32 bytes which contains the actual Ed25519 private key scalar
    let keyData: Data
    if seed.count == 192 {
        // Cardano extended key format: first 32 bytes is the private key scalar
        keyData = seed.prefix(32)
    } else if seed.count == 32 {
        keyData = seed
    } else {
        return nil
    }

    let digest = SHA512.hash(data: keyData)  // ❌ STILL WRONG for Cardano!
    var scalar = Data(digest.prefix(32))
    scalar[0] &= 0xF8
    scalar[31] &= 0x3F
    scalar[31] |= 0x40
    return scalar
}
```

**What This Fixed:**
- ✅ Handles 192-byte extended key format from WalletCore
- ✅ Extracts the first 32 bytes (spending key scalar)

**What's Still Wrong:**
- ❌ **Still applies SHA512 hash to the key data**
- ❌ This double-hashes Cardano keys (PBKDF2-SHA512 + SHA512)
- ❌ Causes payment credentials to differ from Trust Wallet

### What the Full Fix Should Be

According to CARDANO_KEY_FIX.md:

**Create new Cardano-specific function:**
```swift
/// Clamps Cardano BIP32-Ed25519 extended key without additional hashing.
/// For Cardano (Icarus), keys are already derived via PBKDF2-HMAC-SHA512 (4096 iterations).
/// This function applies Ed25519 clamping directly to the scalar bytes.
static func cardanoClampedScalar(from extendedKey: Data) -> Data? {
    let scalarBytes: Data

    switch extendedKey.count {
    case 96, 128:
        // Standard formats: first 32 bytes is the Ed25519 scalar
        scalarBytes = extendedKey.prefix(32)
    case 192:
        // WalletCore format: first 32 bytes is spending key scalar
        scalarBytes = extendedKey.prefix(32)
    case 32:
        // Already just the scalar
        scalarBytes = extendedKey
    default:
        return nil
    }

    // Apply Ed25519 clamping WITHOUT SHA512 hashing
    var scalar = Data(scalarBytes)
    scalar[0] &= 0xF8   // Clear lowest 3 bits
    scalar[31] &= 0x3F  // Clear highest 2 bits
    scalar[31] |= 0x40  // Set bit 6

    return scalar
}
```

**Update routing function:**
```swift
static func clampThenUniformScalar(from seed: Data, isCardano: Bool = false) -> Data? {
    if isCardano {
        // New correct behavior: no SHA512, just clamp
        guard let clamped = cardanoClampedScalar(from: seed) else { return nil }
        return ed25519UniformFromLittleEndianScalar(clamped)
    } else {
        // Other chains (Solana, etc.): use SHA512 then clamp
        guard let clamped = ed25519ClampedScalar(from: seed) else { return nil }
        return ed25519UniformFromLittleEndianScalar(clamped)
    }
}
```

**Update KeygenViewModel.swift:**
```swift
// In startKeyImportKeygen() for EdDSA chains
var chainSeed: Data?
if isInitiateDevice {
    let isCardano = (chain == .cardano)
    guard let chainKey,
          let serializedChainSeed = Data.clampThenUniformScalar(from: chainKey, isCardano: isCardano) else {
        throw HelperError.runtimeError("Couldn't transform key to scalar for Schnorr key import for chain \(chain.name)")
    }
    chainSeed = serializedChainSeed
}
```

### Address Format

**Vultisig (Enterprise Address):**
```
addr1v8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36zcg293qq
      └─────────────────────────────────────┘
           Payment Credential
```

**Structure:**
- Header: `0x61` (Enterprise address on Production network)
- Payment hash: 28 bytes (Blake2b hash of spending public key)
- Total: 29 bytes + Bech32 encoding

**Why Enterprise:**
- Vultisig's TSS architecture processes **ONE key per chain**
- Base addresses require **TWO keys** (payment + staking)
- Enterprise addresses are fully functional for payments
- Trade-off: No direct staking support from address

---

## Trust Wallet Implementation

### Key Derivation Method

**Algorithm:** Icarus (standard for Shelley-era Cardano)

**Master Key Generation:**
```
BIP39 Mnemonic → Entropy (128-256 bits)
                ↓
        PBKDF2-HMAC-SHA512
        - Password: Entropy
        - Salt: Entropy (same as password)
        - Iterations: 4096
        - Output: 96 bytes
                ↓
        Extended Key (96 bytes):
        - Bytes 0-31:   Private key scalar
        - Bytes 32-63:  IV for signing
        - Bytes 64-95:  Chain code
```

**WalletCore Returns 192 Bytes for Cardano:**
```
Bytes 0-31:    Spending key scalar (private key)
Bytes 32-63:   IV for signing with spending key
Bytes 64-95:   Chain code for spending key derivation
Bytes 96-127:  Spending public key (derived from scalar)
Bytes 128-159: Staking key scalar (private key)
Bytes 160-191: IV for signing with staking key
```

### Ed25519 Clamping

**Applied to the scalar directly (NO SHA512):**
```cpp
scalar[0] &= 0xF8   // Clear bits 0-2
scalar[31] &= 0x3F  // Clear bits 6-7
scalar[31] |= 0x40  // Set bit 6
```

### Derivation Paths (CIP-1852)

**Spending Key:** `m/1852'/1815'/0'/0/0`
**Staking Key:** `m/1852'/1815'/0'/2/0`

**Breakdown:**
- `1852'` = Purpose (year Ada Lovelace died)
- `1815'` = Coin type (year Ada Lovelace was born)
- `0'` = Account #0 (hardened)
- `0` = External chain (role = spending)
- `0` = Address index

### Address Format

**Type:** Base Address (addr1q)

**Structure:**
```
[header:1][payment_hash:28][staking_hash:28] = 57 bytes
```

**Header:** `0x01` (Base address on Production network)

**Example:**
```
addr1q8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z66qwkfy5muwwq8y9a5q9r4d22n9uuvl93y5vvvjre2tguqw3uf6z
      └─────────────────────────────────────┬────────────────────────────────────┘
                    Payment Credential      └── Staking Credential
```

### Key Generation Process

1. Derive spending key using CIP-1852 path
2. Derive staking key using CIP-1852 path
3. Extract 32-byte public keys from extended keys
4. Apply Ed25519 clamping (NO SHA512)
5. Hash with Blake2b (28 bytes each)
6. Combine: `[0x01][payment_hash][staking_hash]`
7. Bech32 encode with "addr" prefix

### Implementation Details

**Language:** C++ with Swift/Kotlin bindings
**Library:** wallet-core
**Crypto:** TrezorCrypto
**Curve:** TWCurveED25519ExtendedCardano (not standard Ed25519)

**Key Code:**
```cpp
// Staking key derivation
Data deriveStakingPrivateKey(const Data& privateKeyData) {
    if (privateKeyData.size() != PrivateKey::cardanoKeySize) return {};
    const auto halfSize = PrivateKey::cardanoKeySize / 2;
    auto stakingPrivKeyData = TW::subData(privateKeyData, halfSize);
    TW::append(stakingPrivKeyData, TW::Data(halfSize));
    return stakingPrivKeyData;
}

// Signing with extended key
const auto privateKey = PrivateKey(privateKeyData, TWCurveED25519ExtendedCardano);
const auto publicKey = privateKey.getPublicKey(TWPublicKeyTypeED25519Cardano);
const auto signature = privateKey.sign(txId);
```

---

## Yoroi Implementation

### Key Derivation Method

**Algorithm:** Icarus (same as Trust Wallet)

**Master Key Generation:**
```javascript
import { mnemonicToEntropy } from 'bip39';

const entropy = mnemonicToEntropy(mnemonic.join(' '));
const rootKey = CardanoWasm.Bip32PrivateKey.from_bip39_entropy(
  Buffer.from(entropy, 'hex'),
  Buffer.from(''), // Optional password
);
```

**PBKDF2 Parameters:**
- Algorithm: PBKDF2-HMAC-SHA512
- Iterations: 4096
- Salt: Entropy (same as password)
- Output: 96 bytes extended key

### Ed25519 Clamping (Icarus Variant)

**Applied to scalar directly (NO SHA512):**
```rust
// Icarus-specific clamping
scalar[0] &= 0xF8   // Clear bits 0-2
scalar[31] &= 0x3F  // Clear bits 6-7
scalar[31] |= 0x40  // Set bit 6
```

**Note:** Icarus also clears bits 3-5 during intermediate steps (different from Byron/Ledger)

### Derivation Paths (CIP-1852)

**JavaScript Implementation:**
```javascript
function harden(num: number): number {
  return 0x80000000 + num;
}

const rootKey = CardanoWasm.Bip32PrivateKey.from_bip39_entropy(...);

const accountKey = rootKey
  .derive(harden(1852))  // purpose
  .derive(harden(1815))  // coin type
  .derive(harden(0));    // account #0

// Spending key
const utxoPubKey = accountKey
  .derive(0)    // external chain (role=0)
  .derive(0)    // index
  .to_public();

// Staking key
const stakeKey = accountKey
  .derive(2)    // staking chain (role=2)
  .derive(0)    // index
  .to_public();
```

**Key Paths:**
- **Spending Key (External):** `m/1852'/1815'/0'/0/0`
- **Change Addresses (Internal):** `m/1852'/1815'/0'/1/i`
- **Staking Key:** `m/1852'/1815'/0'/2/0`

### Address Format

**Type:** Base Address (addr1q)

**Generation Process:**
1. Hash spending public key → payment credential (28 bytes)
2. Hash staking public key → staking credential (28 bytes)
3. Combine with header byte → 57 bytes total
4. Bech32 encode with "addr" prefix

**Address Features:**
- Supports staking delegation directly from address
- Uses both spending and staking keys
- Generates multiple addresses from same account (privacy)
- External addresses for receiving
- Internal addresses for change

### Implementation Details

**Language:** Rust with WASM bindings for JavaScript
**Library:** cardano-serialization-lib
**Type:** Browser extension and mobile wallet
**Built by:** EMURGO

**Key to Address Conversion:**
- Keys must be converted to raw format via `.to_raw_key()`
- Raw keys are then hashed with Blake2b (28 bytes)
- Credentials combined to create address

### Byron Legacy Support

Yoroi also supports Byron-era addresses:
- **Purpose:** `44'` instead of `1852'`
- **Format:** Base58 encoded (DdzFF prefix)
- **Method:** Random HD or Sequential HD
- Maintained for backward compatibility

---

## Lace Implementation

### Key Derivation Method

**Algorithm:** Icarus (same as Trust Wallet and Yoroi)

**Master Key Generation:**
Lace uses the same method through cardano-serialization-lib:
- Algorithm: PBKDF2-HMAC-SHA512
- Iterations: 4096
- Salt: Entropy
- Output: 96 bytes extended key

### Ed25519 Clamping

**Same as Yoroi (Icarus method):**
```javascript
scalar[0] &= 0xF8   // Clear bits 0-2
scalar[31] &= 0x3F  // Clear bits 6-7
scalar[31] |= 0x40  // Set bit 6
```

### Derivation Paths (CIP-1852)

**Implementation:**
```javascript
// Lace follows CIP-1852 standard
const derivationPath = ['1852H', '1815H', '0H', '0', '0'];

// Returns Bip32PrivateKey in formats:
// - "ed25519e_sk1..." (extended key)
// - "xprv..." (BIP32 format)
```

**Key Paths:**
- **Payment Key:** `m/1852'/1815'/0'/0/0`
- **Staking Key:** `m/1852'/1815'/0'/2/0`

### Address Format

**Type:** Base Address (addr1q)

**Implementation:**
Lace uses the IntersectMBO cardano-addresses library:

```bash
# Command-line example
cardano-address address payment \
  --payment-verification-key $(cat payment.vkey) | \
cardano-address address delegation \
  --delegation-verification-key $(cat stake.vkey)
```

**Address Properties:**
- Base addresses with both payment and staking credentials
- Supports direct staking from address
- Staking rights exercised by owner of staking key
- Full delegation capabilities

### Implementation Details

**Language:** TypeScript
**Library:** cardano-js-sdk (19 packages)
**Built by:** Input Output Global (IOG)
**Type:** Browser extension wallet

**cardano-js-sdk Features:**
- Domain model written in TypeScript
- Supports hardware wallets (Ledger, Trezor)
- Various key management options
- Battle-tested tooling from IOG

**Staking Support:**
- After delegating, posts delegation certificate on-chain
- Certificate contains stake key + stake pool identifier
- Full rewards management
- Portfolio growth through staking

---

## Comparison Matrix

### Key Derivation Method

| Wallet | Method | PBKDF2 Iterations | Additional Hashing | Clamping |
|--------|--------|-------------------|-------------------|----------|
| **Vultisig (Current)** | Icarus | 4096 | ❌ **SHA512 (WRONG)** | Standard Ed25519 |
| **Trust Wallet** | Icarus | 4096 | ✅ None | Standard Ed25519 |
| **Yoroi** | Icarus | 4096 | ✅ None | Icarus variant |
| **Lace** | Icarus | 4096 | ✅ None | Icarus variant |

### Derivation Paths (CIP-1852)

| Wallet | Spending Key | Staking Key | Change Addresses | Standard |
|--------|--------------|-------------|------------------|----------|
| **Vultisig** | `m/1852'/1815'/0'/0/0` | ❌ Not used | ❌ Not supported | CIP-1852 |
| **Trust Wallet** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | Supported | CIP-1852 |
| **Yoroi** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | `m/1852'/1815'/0'/1/i` | CIP-1852 |
| **Lace** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | Supported | CIP-1852 |

### Address Format

| Wallet | Format | Prefix | Structure | Staking Support | Length |
|--------|--------|--------|-----------|-----------------|--------|
| **Vultisig** | Enterprise | addr1v | Payment only | ❌ No | 29 bytes |
| **Trust Wallet** | Base | addr1q | Payment + Staking | ✅ Yes | 57 bytes |
| **Yoroi** | Base | addr1q | Payment + Staking | ✅ Yes | 57 bytes |
| **Lace** | Base | addr1q | Payment + Staking | ✅ Yes | 57 bytes |

### Extended Key Format

| Wallet | Extended Key | Spending Key | Staking Key | Key Export |
|--------|-------------|--------------|-------------|------------|
| **Vultisig** | 192 bytes (from WalletCore) | Bytes 0-31 | ❌ Not used | Only spending |
| **Trust Wallet** | 192 bytes | Bytes 0-31 | Bytes 128-159 | Both generated |
| **Yoroi** | 96 bytes | First 32 bytes | Separate derivation | On-demand |
| **Lace** | 96 bytes | First 32 bytes | Separate derivation | On-demand |

### Implementation Stack

| Wallet | Language | Core Library | Crypto Library | Platform |
|--------|----------|--------------|----------------|----------|
| **Vultisig** | Swift | WalletCore | CryptoKit | iOS/macOS |
| **Trust Wallet** | C++ | wallet-core | TrezorCrypto | Multi-platform |
| **Yoroi** | Rust/WASM | cardano-serialization-lib | ed25519-bip32 | Browser/Mobile |
| **Lace** | TypeScript | cardano-js-sdk | cardano-serialization-lib | Browser |

---

## The Remaining Issues

### Issue 1: Double SHA512 Hashing (Technical)

**Cardano key derivation process (correct):**
```
BIP39 Mnemonic → Entropy
                ↓
        PBKDF2-HMAC-SHA512 (4096 iterations) ← WalletCore does this
                ↓
        Extended Key (96 or 192 bytes)
                ↓
        Extract 32-byte scalar
                ↓
        Apply Ed25519 clamping (NO SHA512) ← Vultisig does SHA512 here (WRONG)
                ↓
        Clamped scalar
```

**What Vultisig currently does:**
```swift
let keyData = seed.prefix(32)  // Extract first 32 bytes
let digest = SHA512.hash(data: keyData)  // ❌ WRONG: Additional SHA512
var scalar = Data(digest.prefix(32))
scalar[0] &= 0xF8
scalar[31] &= 0x3F
scalar[31] |= 0x40
```

**What other wallets do:**
```cpp
// Trust Wallet (correct)
var scalar = Data(keyData)  // Use key directly, NO SHA512
scalar[0] &= 0xF8
scalar[31] &= 0x3F
scalar[31] |= 0x40
```

### Why This Is Wrong

1. **WalletCore already does PBKDF2-HMAC-SHA512** (4096 iterations) when deriving keys
2. The extended private key from WalletCore is **already hashed and derived**
3. Applying SHA512 **again** corrupts the key material
4. Standard Ed25519 (Solana, etc.) uses SHA512 on raw seeds; **Cardano does not**

### Impact of Double SHA512

**Current State (With Bug):**
- ❌ Payment credentials differ from Trust Wallet/Yoroi/Lace
- ❌ Addresses generated from same seed phrase are completely different
- ❌ Cannot import Vultisig wallets into other Cardano wallets
- ❌ Cannot import other wallet seeds and get matching addresses

**After SHA512 Fix:**
- ✅ Payment credentials will match Trust Wallet/Yoroi/Lace
- ✅ Key derivation will be correct
- ⚠️ Still different address format (addr1v vs addr1q) due to enterprise vs base
- ⚠️ Still different addresses = still different balances (see Issue 2)

### Issue 2: Different Address Formats = Different Balances (User Impact)

**CRITICAL LIMITATION:** Even after fixing the SHA512 issue, different address formats mean **different addresses on the blockchain**, which means **DIFFERENT BALANCES**.

#### Scenario 1: User Has Trust Wallet with 100 ADA

```
User imports same seed phrase into Vultisig expecting to see their 100 ADA...

Trust Wallet:
  Address:  addr1q8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z66qwkfy5...
  Balance:  100 ADA ✅

Vultisig:
  Address:  addr1v8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36zcg293qq
  Balance:    0 ADA ❌ (different address, no funds!)
```

**User Impact:**
- 😕 User is confused: "I imported my seed phrase but my balance is zero!"
- ❌ Cannot access Trust Wallet funds from Vultisig
- ⚠️ Must manually transfer 100 ADA from Trust Wallet address to Vultisig address

#### Scenario 2: User Has Vultisig with 100 ADA

```
User imports same seed phrase into Trust Wallet expecting to see their 100 ADA...

Vultisig:
  Address:  addr1v8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36zcg293qq
  Balance:  100 ADA ✅

Trust Wallet:
  Address:  addr1q8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z66qwkfy5...
  Balance:    0 ADA ❌ (different address, no funds!)
```

**User Impact:**
- 😕 User is confused: "I imported my seed phrase but my balance is zero!"
- ❌ Cannot access Vultisig funds from Trust Wallet
- ⚠️ Must manually transfer 100 ADA from Vultisig address to Trust Wallet address

#### Why This Happens

**Cardano addresses are like physical mailboxes:**
- `addr1q...` = Mailbox at 123 Base Street
- `addr1v...` = Mailbox at 123 Enterprise Avenue

Even though they're both generated from the same keys (same "owner"), they're **different mailboxes** at **different locations** on the blockchain.

**Blockchain perspective:**
```
Cardano Blockchain:
  │
  ├─ addr1q8hrfv...xyz (Base Address)
  │  ├─ UTXO 1: 50 ADA
  │  └─ UTXO 2: 50 ADA
  │  Total: 100 ADA
  │
  └─ addr1v8hrfv...abc (Enterprise Address)
     └─ (empty, no UTXOs)
     Total: 0 ADA
```

#### What "Same Payment Credential" Actually Means

After the SHA512 fix, payment credentials will match:
```
Trust Wallet Payment Credential:  8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z
Vultisig Payment Credential:      8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z
                                  ✅ IDENTICAL
```

**BUT:**
```
Trust Wallet Full Address:  addr1q + [payment] + [staking]  = addr1q8hrfv...w3uf6z
Vultisig Full Address:      addr1v + [payment]              = addr1v8hrfv...g293qq
                            ❌ DIFFERENT ADDRESSES
```

**Analogy:**
- Payment credential = Your name
- Address format = Your address type (home vs office)
- Same name, different locations = different mailboxes = different mail

#### User Experience Impact

**What users expect:**
```
"I have the same seed phrase, so I should see the same wallet and balance everywhere!"
```

**What actually happens:**
```
Same seed phrase → Same keys → Different address formats → Different addresses → Different balances
```

**This violates user expectations and causes confusion!**

### Solutions to Issue 2

**Option A: Keep Enterprise Addresses (Current - Simple but Confusing)**
- ✅ No code changes needed (after SHA512 fix)
- ❌ Users will be confused by different balances
- ❌ Cannot seamlessly migrate between wallets
- ⚠️ Must document this clearly for users

**Option B: Implement Base Address Support (Future - True Compatibility)**
- ✅ Same addresses as Trust Wallet/Lace/Yoroi
- ✅ Same balances (true compatibility)
- ✅ Seamless wallet migration
- ❌ Requires significant architectural changes (process 2 keys per chain)
- ❌ Several days of development work

**Option C: Hybrid Approach (Future - Best UX)**
- Support both Enterprise and Base addresses
- Let users choose when importing
- Detect which address type has funds and suggest that one
- Most flexible but most complex

---

## WalletCore Derivation Methods Investigation

### Research Question
Can we use WalletCore's derivation path methods to support Lace/Yoroi-style derivation?

### Answer: No Need - Vultisig Already Uses Correct Path ✅

**Finding:** All modern Cardano wallets (Trust Wallet, Lace, Yoroi, Vultisig) use the **exact same CIP-1852 derivation path**.

**WalletCore's default for Cardano:**
```swift
wallet.getKeyForCoin(coin: .cardano)
// Returns key for: m/1852'/1815'/0'/0/0 (CIP-1852 spending key)
```

**This is already what Vultisig uses and what all other wallets use!**

### WalletCore Methods Available

#### 1. `getKeyForCoin(coin:)` - Default Derivation (✅ Current Usage)
```swift
let privateKey = wallet.getKeyForCoin(coin: .cardano)
// → m/1852'/1815'/0'/0/0 (CIP-1852 standard)
```
- Uses the default derivation path for the specified coin
- For Cardano: Always uses CIP-1852 spending key path
- **This is what Vultisig currently uses**

#### 2. `getKeyDerivation(coin:derivation:)` - Predefined Enum
```swift
let privateKey = wallet.getKeyDerivation(coin: .solana, derivation: .solanaSolana)
```
- Uses predefined `Derivation` enum values
- Examples: `.solanaSolana` (Phantom), `.bitcoinSegwit`, `.bitcoinLegacy`
- **Limited to predefined enum options only**
- **No Cardano-specific options exist** (because CIP-1852 is the only standard)

#### 3. `getDerivedKey(coin:account:change:address:)` - Custom BIP44 Components
```swift
let key = wallet.getDerivedKey(coin: .cardano, account: 0, change: 0, address: 0)
// → m/1852'/1815'/0'/0/0 (same as default)

let stakingKey = wallet.getDerivedKey(coin: .cardano, account: 0, change: 2, address: 0)
// → m/1852'/1815'/0'/2/0 (staking key)
```
- Builds path from BIP44 components
- Format: `m/purpose'/coin_type'/account'/change/address`
- **Could be used to derive staking key separately**

#### 4. `getKey(coin:derivationPath:)` - DerivationPath Object
```swift
// Requires DerivationPath object (not available in Vultisig's WalletCore bindings)
let path = DerivationPath(purpose: .bip44, coin: cardano, account: 0, change: 0, address: 0)
let privateKey = wallet.getKey(coin: .cardano, derivationPath: path)
```
- Takes a `DerivationPath` **object**, not a raw string
- **Not exposed in Vultisig's WalletCore version**

### Key Finding: No Alternative Derivation Needed

**Unlike Solana, Cardano has ONE standard:**
- ✅ All wallets use CIP-1852
- ✅ No wallet-specific variations
- ✅ No need to extend `DerivationPath` enum for Cardano

**Comparison:**

| Chain | Standards | Vultisig Support |
|-------|-----------|------------------|
| **Solana** | BIP-44 (default) + Phantom style | ✅ Has `DerivationPath.phantom` |
| **Cardano** | CIP-1852 only (universal) | ✅ Already correct, no options needed |
| **Bitcoin** | Legacy + SegWit + Native SegWit | ❌ Only default |
| **Ethereum** | BIP-44 only (universal) | ✅ Already correct |

### Derivation Path Comparison

| Wallet | Spending Key Path | Staking Key Path | Current Vultisig |
|--------|------------------|------------------|------------------|
| **Trust Wallet** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | ✅ Same spending |
| **Yoroi** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | ✅ Same spending |
| **Lace** | `m/1852'/1815'/0'/0/0` | `m/1852'/1815'/0'/2/0` | ✅ Same spending |
| **Vultisig** | `m/1852'/1815'/0'/0/0` | ❌ Not derived | ✅ Already correct |

### Conclusion: No Derivation Path Changes Needed

**What we learned:**
1. ✅ Vultisig already uses correct CIP-1852 derivation path
2. ✅ All Cardano wallets use the same path (no variations)
3. ✅ No need to add Cardano options to `DerivationPath` enum
4. ❌ The issue is NOT derivation paths
5. ❌ The issue IS double SHA512 hashing + address format

**What could be done with `getDerivedKey` (future):**
```swift
// Derive staking key separately for base address support
let spendingKey = wallet.getKeyForCoin(coin: .cardano)
// → m/1852'/1815'/0'/0/0

let stakingKey = wallet.getDerivedKey(coin: .cardano, account: 0, change: 2, address: 0)
// → m/1852'/1815'/0'/2/0

// Process both through TSS to create base address (addr1q)
```

But this requires architectural changes (TSS processing multiple keys per chain).

---

## Recommended Next Steps

### 1. Implement the Full Fix (High Priority)

**Files to Modify:**
- `VultisigApp/Extensions/DataExtension.swift`
- `VultisigApp/View Models/KeygenViewModel.swift`
- `VultisigApp/Model/Vault.swift` (add versioning)

**Changes Required:**

**A. Create Cardano-specific clamping function:**
```swift
// In DataExtension.swift
static func cardanoClampedScalar(from extendedKey: Data) -> Data? {
    let scalarBytes: Data

    switch extendedKey.count {
    case 96, 128:
        scalarBytes = extendedKey.prefix(32)
    case 192:
        // WalletCore format: first 32 bytes is spending key scalar
        scalarBytes = extendedKey.prefix(32)
    case 32:
        scalarBytes = extendedKey
    default:
        return nil
    }

    // Apply Ed25519 clamping WITHOUT SHA512 hashing
    var scalar = Data(scalarBytes)
    scalar[0] &= 0xF8   // Clear lowest 3 bits
    scalar[31] &= 0x3F  // Clear highest 2 bits
    scalar[31] |= 0x40  // Set bit 6

    return scalar
}
```

**B. Update routing function:**
```swift
// In DataExtension.swift
static func clampThenUniformScalar(from seed: Data, isCardano: Bool = false) -> Data? {
    if isCardano {
        // Cardano: no SHA512, just clamp
        guard let clamped = cardanoClampedScalar(from: seed) else { return nil }
        return ed25519UniformFromLittleEndianScalar(clamped)
    } else {
        // Other chains (Solana, etc.): use SHA512 then clamp
        guard let clamped = ed25519ClampedScalar(from: seed) else { return nil }
        return ed25519UniformFromLittleEndianScalar(clamped)
    }
}
```

**C. Update KeygenViewModel:**
```swift
// In startKeyImportKeygen()
var chainSeed: Data?
if isInitiateDevice {
    let isCardano = (chain == .cardano)
    guard let chainKey,
          let serializedChainSeed = Data.clampThenUniformScalar(from: chainKey, isCardano: isCardano) else {
        throw HelperError.runtimeError("Couldn't transform key to scalar for Schnorr key import for chain \(chain.name)")
    }
    chainSeed = serializedChainSeed
}
```

### 2. Add Vault Versioning (Medium Priority)

**Add to Vault.swift:**
```swift
/// Tracks Cardano key derivation version for migration support
/// nil = legacy (pre-fix with double SHA512), 1 = CIP-1852 correct derivation
var cardanoKeyVersion: Int?

extension Vault {
    /// Detects if this vault needs Cardano key derivation migration
    var needsCardanoMigration: Bool {
        let hasCardano = chains.contains(.cardano)
        guard hasCardano else { return false }

        guard let version = cardanoKeyVersion else {
            return true  // Legacy vault without version tracking
        }

        return version < 1  // Current version is 1
    }
}
```

**Set version for new vaults:**
```swift
// In KeygenViewModel after processing chains
if chains.contains(.cardano) {
    self.vault.cardanoKeyVersion = 1
}
```

### 3. Test Thoroughly (High Priority)

**Test Mnemonic:**
```
foil unlock label festival survey evil visa organ wealth profit figure muscle
```

**Expected Results (after fix):**

**Payment Credential (should match):**
```
8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z
```

**Vultisig Address (Enterprise):**
```
addr1v8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36zcg293qq
      └─────────────────────────────────────┘
           Payment Credential (should match)
```

**Trust Wallet Address (Base):**
```
addr1q8hrfv2lf650qt0dpt09l0szgj7wcgxh5td7ujqqkkx36z66qwkfy5muwwq8y9a5q9r4d22n9uuvl93y5vvvjre2tguqw3uf6z
      └─────────────────────────────────────┬────────────────────────────────────┘
           Payment Credential (should match)  Staking Credential (different - OK)
```

**Validation:**
- ✅ Payment credential portion matches exactly
- ✅ Both addresses are valid Cardano addresses
- ✅ Both can receive/send ADA
- ⚠️ Different prefixes (addr1v vs addr1q) is expected and OK

### 4. Consider Base Address Support (Future Enhancement)

**Requirements:**
- Process BOTH spending and staking keys through TSS
- Store multiple public keys per chain
- Modify keysign to support multiple keys
- Update vault data structure
- Migration path for existing vaults

**Estimated Effort:** Several days of development

**Benefits:**
- ✅ Exact Trust Wallet compatibility
- ✅ Direct staking support
- ✅ Industry standard address format

**Approach:**
1. Extend TSS key import to process multiple keys per chain
2. Add `stakingPublicKey` field to `ChainPublicKey` model
3. Update `CoinFactory` to generate base addresses when staking key available
4. Implement migration for existing enterprise address vaults
5. Add UI for users to choose address type

### 5. Document for Users

**Create user-facing documentation:**
- Explain enterprise vs base addresses
- Both are valid and functional
- Enterprise = payment only
- Base = payment + staking
- Vultisig uses enterprise due to TSS architecture
- Can transfer to base address wallets anytime

---

## Standards & References

### Cardano Standards
- [CIP-1852: HD Wallets for Cardano](https://cips.cardano.org/cip/CIP-1852) - Derivation path standard
- [CIP-3: Wallet Key Generation](https://cips.cardano.org/cip/CIP-3) - Extended key structure
- [CIP-11: Staking Key Chain](https://cips.cardano.org/cip/CIP-11) - Staking key derivation
- [CIP-16: Cryptographic Key Serialisation](https://github.com/cardano-foundation/CIPs/blob/master/CIP-0016/README.md) - Key format specs
- [CIP-19: Cardano Addresses](https://cips.cardano.org/cip/CIP-19) - Address format specification
- [Master Key Generation - Cardano Wallet](https://input-output-hk.github.io/adrestia/cardano-wallet/concepts/master-key-generation) - Icarus algorithm

### Trust Wallet
- [Trust Wallet Core Repository](https://github.com/trustwallet/wallet-core)
- [Cardano Signer Implementation](https://github.com/trustwallet/wallet-core/blob/master/src/Cardano/Signer.cpp)
- [Registry.json Configuration](https://github.com/trustwallet/wallet-core/blob/master/registry.json)

### Yoroi
- [Cardano Serialization Library](https://github.com/Emurgo/cardano-serialization-lib)
- [Generating Keys Documentation](https://github.com/Emurgo/cardano-serialization-lib/blob/master/doc/getting-started/generating-keys.md)

### Lace
- [Lace Wallet Repository](https://github.com/input-output-hk/lace)
- [Cardano JS SDK](https://github.com/input-output-hk/cardano-js-sdk)
- [Cardano Addresses Library](https://github.com/IntersectMBO/cardano-addresses)

### BIP32-Ed25519
- [BIP32-Ed25519 Specification (PDF)](https://cardano-foundation.github.io/cardano-wallet/design/concepts/Ed25519_BIP.pdf)
- [StricaHQ BIP32-Ed25519 Implementation](https://github.com/StricaHQ/bip32ed25519)

---

## Conclusion

### Summary

1. **All industry wallets follow the same standard:**
   - Icarus master key generation (PBKDF2-HMAC-SHA512, 4096 iterations)
   - CIP-1852 derivation paths (`m/1852'/1815'/0'/0/0`)
   - BIP32-Ed25519 (not standard BIP32)
   - Base addresses (addr1q) with spending + staking keys

2. **Vultisig's derivation path is correct:**
   - ✅ Already uses CIP-1852 (`m/1852'/1815'/0'/0/0`)
   - ✅ Same path as Trust Wallet, Lace, and Yoroi
   - ✅ No need to add derivation path options for Cardano

3. **Vultisig's current technical issue:**
   - ❌ Applies additional SHA512 to Cardano keys (double hashing)
   - ❌ Causes payment credentials to differ from other wallets
   - ⚠️ Partial fix applied Feb 2, 2026 (handles 192-byte format)
   - ⚠️ Full fix documented but not implemented yet

4. **Vultisig's architectural difference:**
   - Uses Enterprise addresses (addr1v) due to TSS constraints
   - One key per chain (not two like base addresses require)
   - Both formats are valid and functional

5. **🚨 CRITICAL USER IMPACT: Different Addresses = Different Balances**
   - ❌ Even after fixing SHA512, different address formats mean different balances
   - ❌ Users importing same seed phrase will see 0 ADA in different wallet
   - ❌ Cannot seamlessly migrate between Vultisig and Trust Wallet/Lace/Yoroi
   - ⚠️ This will cause significant user confusion

### Action Items

**Immediate (High Priority):**
1. ✅ Implement full fix for double SHA512 hashing
   - Create `cardanoClampedScalar()` function (no SHA512)
   - Update `clampThenUniformScalar()` to route Cardano correctly
   - Update `KeygenViewModel` to pass `isCardano: true`
2. ✅ Add vault versioning for migration support
3. ✅ Test with known seed phrase to verify credentials match
4. ✅ Ensure SwiftLint compliance
5. ⚠️ **Document user impact clearly:**
   - Warn users that importing Trust Wallet seed won't show their balance
   - Explain they need to manually transfer funds
   - Consider showing this in the import flow

**Future Enhancements (Medium Priority):**
1. **Consider base address support** (requires architectural changes)
   - Process both spending + staking keys through TSS
   - Store multiple public keys per chain
   - Modify keysign to support multiple keys
   - This is the ONLY way to achieve true compatibility
2. Implement migration UI for legacy vaults
3. Add address format selection during import
4. Detect which address has funds and guide users

**Decision Needed:**
- Should Vultisig implement base address support for true compatibility?
- Or accept Enterprise addresses with clear user documentation?
- Trade-off: Development time vs. user experience

**The SHA512 fix is straightforward to implement. However, the address format difference will still cause user confusion. Consider whether base address support is worth the architectural changes for better UX.** 🤔

---

**Document Version:** 1.0
**Last Updated:** February 4, 2026
**Authors:** Vultisig Development Team
