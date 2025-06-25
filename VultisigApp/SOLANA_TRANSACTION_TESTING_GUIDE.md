# Solana Transaction Testing Guide

This guide explains how to test Solana transactions and capture the actual transaction data for Blockaid security scanning.

## What We've Added

1. **Transaction Logging in `Solana.swift`**:
   - Logs pre-signed input data (hex and base64)
   - Logs image hash for signing
   - Logs final signed transaction (base64 and hex)
   - Prints transaction data for easy copy/paste

2. **Security Scan Logging in `BlockaidProvider.swift`**:
   - Logs incoming scan request details
   - Shows transaction data being sent to Blockaid

3. **Enhanced Security Service**:
   - Now properly creates Solana transaction data for security scanning
   - Sends base64-encoded transaction message to Blockaid

## How to Test

### 1. Run the App
```bash
# Build and run on simulator
xcodebuild -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' run
```

### 2. Create a Solana Transaction
1. Open the app in the simulator
2. Navigate to a Solana wallet
3. Initiate a send transaction
4. The transaction data will be logged in the console

### 3. View Logs
Look for these log entries in the Xcode console:

```
📦 SOLANA PRE-SIGNED INPUT DATA:
   - Input Data (hex): ...
   - Input Data (base64): ...
   - Input Data Length: ... bytes

🔐 SOLANA PRE-SIGNING OUTPUT:
   - Image Hash: ...

✅ SOLANA SIGNED TRANSACTION:
   - Raw Transaction (base64): ...
   - Raw Transaction (hex): ...
   - Transaction Hash: ...
   - Transaction Length: ... bytes

🚀 SOLANA TRANSACTION DATA FOR TESTING:
================================
Base64 Encoded Transaction:
[TRANSACTION DATA HERE]
================================
Hex Encoded Transaction:
[HEX DATA HERE]
================================
```

### 4. Security Scan Logs
When security scanning is enabled, you'll also see:

```
📦 Created Solana transaction data for security scan: [BASE64 DATA]

🚀 SOLANA SECURITY SCAN REQUEST:
   - From Address: ...
   - To Address: ...
   - Amount: ...
   - Data: [BASE64 TRANSACTION]
   - Data Length: ... characters
   - Decoded Data (hex): ...
   - Decoded Data Length: ... bytes
```

## Example Transaction Data

Here's an example of what a Solana transaction might look like:

**Base64 (what's sent to Blockaid):**
```
AQABAwZX5V1... (truncated for brevity)
```

**Hex (decoded):**
```
01000103065fe55d... (truncated for brevity)
```

## Testing with Blockaid

1. Copy the base64 transaction data from the logs
2. Use it to test the Blockaid API directly:

```bash
curl -X POST https://api.vultisig.com/blockaid/v0/solana/message/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "data": {
      "message": "[PASTE BASE64 TRANSACTION HERE]",
      "accountAddress": "[FROM ADDRESS]"
    },
    "metadata": {
      "domain": "vultisig.com"
    }
  }'
```

## Notes

- Solana is currently **not supported in GA** by Blockaid (returns this error)
- Bitcoin endpoints return 404 errors
- Only EVM chains are fully functional for transaction scanning
- The transaction data logged can be used to test when Blockaid adds Solana support

## Troubleshooting

If you don't see logs:
1. Make sure you're running in Debug configuration
2. Check the Console app on macOS and filter by "solana-helper" or "security"
3. Ensure you have a Solana wallet with balance to create transactions 