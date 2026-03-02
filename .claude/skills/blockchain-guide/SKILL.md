---
name: blockchain-guide
description: Blockchain architecture, chain services, TSS keygen/keysign, and vault key management.
user-invocable: false
---

# Blockchain Architecture Guide

Vultisig supports 40+ blockchains using threshold signature schemes (TSS) with three cryptographic algorithms.

## Overview

| Algorithm | Library | Curve | Chains |
|-----------|---------|-------|--------|
| ECDSA | `godkls` | secp256k1 | Bitcoin, EVM, THORChain, Cosmos, Ripple, Tron (34 chains) |
| EdDSA | `goschnorr` | Ed25519 | Solana, Cardano, Polkadot, Ton, Sui (6 chains) |
| ML-DSA | `vscore` | ML-DSA-44 | Post-quantum support (future) |

## Key Coordination

`BlockChainService` (`Services/BlockChainService.swift`) coordinates chain-specific operations:
- Fetches chain-specific transaction parameters (`BlockChainSpecific`)
- Normalizes fees (UTXO x2.5, EVM x1.5 multipliers)
- Manages caching and Solana blockhash refresh

## Chain Types

`ChainType` enum (`States/ChainType.swift`):
- `.UTXO` - Bitcoin, Litecoin, Dash, etc.
- `.Cardano` - Special UTXO (EdDSA)
- `.EVM` - Ethereum, Polygon, etc.
- `.Solana`, `.Sui`, `.Polkadot`, `.Ton` - EdDSA chains
- `.THORChain`, `.Cosmos`, `.Ripple`, `.Tron` - ECDSA chains

## Supporting Files

- **Chain details:** See `chains.md` in this skill directory
- **Keygen/Keysign flows:** See `keygen-keysign.md` in this skill directory
- **Endpoint management:** `Utils/Endpoint.swift` (~1500 lines, centralized URLs)
- **Vault model:** `Model/Vault.swift` (SwiftData, holds keys + coins)
