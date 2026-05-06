# Test fixtures

## `LimitSwapMemos.json`

Canonical THORChain limit-swap memo test vectors. **iOS-canonical for Phase 1**
(see `wiki/pages/projects/vultisig/thorchain-limit-swap/spec/proposal.md`) until
vultisig/vultisig-sdk#312 lands its own fixture file. Reconciliation is a
follow-up task; if SDK fixtures diverge from these, SDK wins (cross-platform
authority) and these regenerate.

### Schema

```json
{
  "vectors": [
    {
      "name": "btc_to_eth_24h_non_referred",
      "inputs": {
        "source_asset": "BTC.BTC",
        "source_amount": "100000000",          // BigInt-encoded as string for cross-platform safety
        "source_decimals": 8,
        "target_asset": "ETH.ETH",
        "dest_addr": "0x1234...",
        "target_price": "16",                  // Decimal-encoded as string for cross-platform safety
        "expiry_hours": 24,                    // {12, 24, 72}
        "affiliate": "vi",                     // or "myref/vi" for referred users
        "affiliate_bps": "50"                  // or "10/35" for referred
      },
      "expected_memo": "=<:ETH.ETH:0x1234...:1600000000/14400/0:vi:50"
    }
  ]
}
```

### Coverage

24 vectors: 4 pairs × 3 expiries × {non-referred, referred}.

- BTC → ETH at `16` ETH/BTC (1 BTC source)
- ETH → BTC at `0.0625` BTC/ETH (1 ETH source)
- USDT → BTC at `0.00001` BTC/USDT (50,000 USDT source, 6 decimals)
- BTC → RUNE at `6000` RUNE/BTC (1 BTC source)

### Frozen post-§0.D

Once committed, these vectors are **frozen**. Any change requires a code-review
explanation of why the limit-swap memo semantics changed.
