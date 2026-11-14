# Perps test vectors

Generators for the fixed vectors the perps tests pin. Each one uses only
fictional keys (the SDK's public test key `0x0123…0123` and chain code `c9f3…ddee`)
and prints JSON; nothing is sent anywhere.

| script | pinned by | oracle |
|---|---|---|
| `gen_exchange_sdk.py` | `HyperliquidExchangeDryRunTests` | hyperliquid-python-sdk `signing.py` / `exchange.py` |
| `gen_cctp.mjs` | `PerpsFlowsTests` (CCTP deposit) | Circle `encodeForwardHookData` + viem `hashTypedData` |
| `gen_trading_address.mjs` | `PerpsTradingAccountTests` | @scure/bip32 non-hardened derivation |
| `gen_trading_signatures.mjs` | `KeysignDerivationTests` | @scure/bip32 + @noble/curves signatures |

Versions the vectors were generated with: hyperliquid-python-sdk 0.24.0,
eth-account 0.13.7, msgpack 1.2.4 (Python 3.12); viem, @scure/bip32 and
@noble/curves from npm (the outputs are fixed by BIP-32, EIP-712 and Circle's
documented encoding, not by a library version).

```
python3 -m venv .venv && .venv/bin/pip install hyperliquid-python-sdk==0.24.0
.venv/bin/python gen_exchange_sdk.py
npm i viem @scure/bip32 @noble/curves && node gen_trading_address.mjs
```
