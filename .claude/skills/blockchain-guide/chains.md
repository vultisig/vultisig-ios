# Chain-Specific Services & Types

## Service Directories

All under `VultisigApp/VultisigApp/Services/`:

| Directory | Chains |
|-----------|--------|
| `UTXO/` | Bitcoin, Bitcoin-Cash, Litecoin, Dogecoin, Dash, Zcash |
| `Evm/` | Ethereum, Avalanche, Polygon, Base, Blast, Arbitrum, Optimism, BSC, Cronos, zkSync, Mantle, Hyperliquid, Sei |
| `Thorchain/` | THORChain (3 networks) |
| `THORChainAPI/` | THORChain REST API client |
| `MayaChainAPI/` | MayaChain REST API client |
| `Cosmos/` | Cosmos, Kujira, Osmosis, dYdX, Terra, Terra-Classic, Noble, Akash |
| `Solana/` | Solana |
| `Cardano/` | Cardano |
| `Polkadot/` | Polkadot |
| `Ton/` | Ton |
| `Sui/` | Sui |
| `Ripple/` | Ripple |
| `Tron/` | Tron |

**Swap/DeFi services:**

| Directory | Purpose |
|-----------|---------|
| `SwapService/` | Swap coordination |
| `1inch/` | DEX aggregator |
| `KyberSwap/` | KyberSwap DEX |
| `LiFi/` | LiFi bridge aggregator |
| `Fee/` | Fee calculation |
| `Rates/` | Crypto exchange rates |

## BlockChainSpecific Enum

**File:** `Services/Keysign/BlockChainSpecific.swift`

Each variant holds chain-specific transaction parameters:

```swift
enum BlockChainSpecific: Codable, Hashable {
    case UTXO(byteFee: BigInt, sendMaxAmount: Bool)
    case Cardano(byteFee: BigInt, sendMaxAmount: Bool, ttl: UInt64)
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt)
    case THORChain(accountNumber: UInt64, sequence: UInt64, fee: UInt64, isDeposit: Bool, transactionType: Int)
    case MayaChain(accountNumber: UInt64, sequence: UInt64, isDeposit: Bool)
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64, transactionType: Int, ibcDenomTrace: ...)
    case Solana(recentBlockHash: String, priorityFee: BigInt, priorityLimit: BigInt, fromAddressPubKey: String?, toAddressPubKey: String?, hasProgramId: Bool)
    case Sui(referenceGasPrice: BigInt, coins: [[String: String]], gasBudget: BigInt)
    case Polkadot(recentBlockHash: String, nonce: UInt64, currentBlockNumber: BigInt, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String, gas: BigInt?)
    case Ton(sequenceNumber: UInt64, expireAt: UInt64, bounceable: Bool, sendMaxAmount: Bool, jettonAddress: String, isActiveDestination: Bool)
    case Ripple(sequence: UInt64, gas: UInt64, lastLedgerSequence: UInt64)
    case Tron(timestamp: UInt64, expiration: UInt64, blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64, blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String, blockHeaderParentHash: String, blockHeaderWitnessAddress: String, gasFeeEstimation: UInt64)
}
```

## Endpoint Organization

**File:** `Utils/Endpoint.swift` (~1500 lines)

Centralized endpoint management with categories:
- **Base:** Vultisig API proxy (`api.vultisig.com`), relay router
- **THORChain:** Mainnet, Chainnet, Stagenet thornode URLs
- **MayaChain:** `mayanode.mayachain.info`
- **Midgard:** Status/explorer endpoints
- **Security:** Blockaid scanning (EVM, Solana, Bitcoin)
- **LP/Pools:** Pool info, liquidity, staking (TCY, yRUNE, yTCY)
- **Swap Trackers:** THORChain, MayaChain, LiFi

## Chain → Signature Type Mapping

**ECDSA (secp256k1) — 34 chains:**
- UTXO: Bitcoin, Bitcoin-Cash, Litecoin, Dogecoin, Dash, Zcash
- EVM: Ethereum (+Sepolia), Avalanche, Polygon, Polygon v2, Base, Blast, Arbitrum, Optimism, BSC, Cronos, zkSync, Mantle, Hyperliquid, Sei
- THORChain: THORChain, THORChain-Chainnet, THORChain-Stagenet, MayaChain
- Cosmos: Cosmos, Kujira, Osmosis, dYdX, Terra, Terra-Classic, Noble, Akash
- Other: Ripple, Tron

**EdDSA (Ed25519) — 5 chains:**
- Solana, Cardano, Polkadot, Ton, Sui
