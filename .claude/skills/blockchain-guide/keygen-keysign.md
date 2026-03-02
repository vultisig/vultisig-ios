# Keygen & Keysign Flows

## TSS Types

**File:** `States/Keygen/TssType.swift`

```swift
enum TssType: String {
    case Keygen       // Create new vault
    case Reshare      // Share redistribution
    case Migrate      // GG20 to DKLS migration
    case KeyImport    // Import existing keys
}
```

## Library Types

**File:** `States/LibType.swift`

```swift
enum LibType: Int, Codable, CaseIterable {
    case GG20 = 0       // Legacy GG20 protocol
    case DKLS = 1       // DKLS protocol (current default)
    case KeyImport = 2  // Key import vaults
}
```

## TSS Libraries

| Library | Import | Algorithm | Usage |
|---------|--------|-----------|-------|
| `godkls` | `import godkls` | ECDSA (secp256k1) | DKLS keygen/keysign |
| `goschnorr` | `import goschnorr` | EdDSA (Ed25519) | Schnorr keygen/keysign |
| `vscore` | `import vscore` | ML-DSA-44 (Dilithium) | Post-quantum keygen/keysign |

## Keygen Implementations (3)

### DKLS Keygen (ECDSA)

**Files:** `Tss/DKLS/DKLSKeygen.swift`, `Tss/DKLS/DKLSHelper.swift`

- Generates secp256k1 key shares via distributed key generation
- Multi-party computation with setup message exchange
- Produces `pubKeyECDSA` for the vault

### Schnorr Keygen (EdDSA)

**File:** `Tss/Schnorr/SchnorrKeygen.swift`

- Generates Ed25519 key shares via Schnorr protocol
- Compatible with Ed25519 standard
- Produces `pubKeyEdDSA` for the vault

### Dilithium Keygen (ML-DSA)

**Files:** `Tss/Dilithium/DilithiumKeygen.swift`, `Tss/Dilithium/DilithiumHelper.swift`

- Generates ML-DSA-44 key shares (post-quantum)
- Module-Lattice-Based Digital Signature Algorithm
- Produces `publicKeyMLDSA44` for the vault

## Keysign Implementations (3)

### DKLS Keysign (ECDSA)

**File:** `Tss/DKLS/DKLSKeysign.swift`

- Signs transactions for secp256k1 chains
- Multi-party threshold signature

### Schnorr Keysign (EdDSA)

**File:** `Tss/Schnorr/SchnorrKeysign.swift`

- Signs transactions for Ed25519 chains

### Dilithium Keysign (ML-DSA)

**File:** `Tss/Dilithium/DilithiumKeysign.swift`

- Signs with ML-DSA-44 (post-quantum)

## KeygenViewModel

**File:** `View Models/KeygenViewModel.swift`

Status tracking:
```swift
enum KeygenStatus {
    case CreatingInstance
    case KeygenECDSA
    case ReshareECDSA
    case ReshareEdDSA
    case KeygenEdDSA
    case KeygenFinished
    case KeygenFailed
}
```

Key methods:
- `startKeygen(context:)` - Routes to correct protocol
- `startKeygenDKLS(context:)` - DKLS key generation
- `startKeygenGG20(context:)` - Legacy GG20 (migration only)
- `startKeyImportKeygen(modelContext:)` - Import existing keys

Flow: Creates vault -> generates ECDSA key -> generates EdDSA key -> (optional) generates ML-DSA key -> saves vault

## KeysignViewModel

**File:** `View Models/KeysignViewModel.swift`

Status tracking:
```swift
enum KeysignStatus {
    case CreatingInstance
    case KeysignECDSA
    case KeysignEdDSA
    case KeysignFinished
    case KeysignFailed
    case KeysignVaultMismatch
}
```

Key methods:
- `startKeysign()` - Routes to correct signing protocol
- `startKeysignDKLS(isImport:)` - DKLS signing
- `startKeysignGG20()` - Legacy GG20 signing
- `getSignedTransaction(keysignPayload:)` - Build signed transaction
- `broadcastTransaction()` - Send to blockchain

## KeysignPayload

**File:** `Services/Keysign/KeysignPayload.swift`

Complete signing request:
```swift
struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String
    let libType: String                    // "GG20", "DKLS", or "KeyImport"
    let skipBroadcast: Bool
    let signData: SignData?
    // ... chain-specific payloads (Tron, Wasm, etc.)
}
```

## Message Exchange Architecture

All TSS operations use a relay server for message exchange:
- **Relay URL:** `api.vultisig.com/router`
- **Session management:** Unique session IDs per operation
- **Message polling:** Devices poll for messages from other parties
- **Threshold:** `ceil(totalSigners * 2/3) - 1`

## Vault Key Management

A vault holds up to 3 public keys:
- `pubKeyECDSA` - For all ECDSA chains (Bitcoin, EVM, Cosmos, etc.)
- `pubKeyEdDSA` - For all EdDSA chains (Solana, Polkadot, etc.)
- `publicKeyMLDSA44` - For post-quantum chains (optional, future)

**Vault types:**
- **Regular:** All chains available, keys generated via TSS
- **Fast:** Server-assisted signing (`localPartyID` starts with "server-")
- **Imported:** Limited to imported chains, keys from mnemonic

Per-chain addresses are derived from the shared public keys using `chainPublicKeys` for chain-specific derivation paths.
