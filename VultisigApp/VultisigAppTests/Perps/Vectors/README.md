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

Dependencies are pinned exactly: `package.json` + `package-lock.json` for Node
(@noble/curves 2.x changed the APIs these scripts use, so stay on 1.9.7) and
`requirements.txt` for Python 3.12. With those versions the three Node scripts
reproduce the pinned addresses, signatures and CCTP digest byte for byte.

```
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python gen_exchange_sdk.py
npm ci && node gen_trading_address.mjs && node gen_trading_signatures.mjs && node gen_cctp.mjs
```
