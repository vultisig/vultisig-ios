# Midgard Action Status → App Status Mapping

## Overview

THORChain and MayaChain transaction status checking uses the Midgard API `/v2/actions` endpoint with the `txid` query parameter.

## Endpoints

- **THORChain Mainnet**: `https://midgard.ninerealms.com/v2/actions?txid={hash}`
- **THORChain Stagenet**: `https://stagenet-midgard.ninerealms.com/v2/actions?txid={hash}`
- **MayaChain**: `https://midgard.mayachain.info/v2/actions?txid={hash}`

## Canonical Status Mapping (Authoritative)

The mapping is based **exclusively** on `action.status`:

| Midgard Status | App Status | TransactionStatusResult |
|----------------|------------|-------------------------|
| `"success"` | SUCCESS | `.confirmed` |
| `"pending"` | PENDING | `.pending` |
| `"refund"` | FAILED_REFUNDED | `.failed(reason:)` |

## Reason Fields (Display-Only)

These fields **do not affect** the canonical status mapping. They are used only to construct user-facing error messages when `AppStatus = FAILED_REFUNDED`.

### Priority Order for Failure Reasons

**Primary Reason** (first available):
1. `action.metadata.refund.reason`
2. `action.metadata.failed.reason`

**Optional Reason Code** (first available):
1. `action.metadata.refund.code`
2. `action.metadata.failed.code`

**Optional Context**:
- `action.metadata.failed.memo` (if present)

### Refund Outbound Transactions

When a transaction is refunded, the outbound transactions (typically the refund outputs) can be found in:
- `action.out[]` - Array of `MidgardTransaction` objects

Each transaction includes:
- `txID` - The transaction hash
- `address` - Recipient address
- `coins` - Array of coins sent (asset + amount)

## Response Structure

```swift
struct THORChainActionsResponse {
    let actions: [MidgardAction]
    let count: String
}

struct MidgardAction {
    let pools: [String]
    let type: String           // e.g., "swap", "refund", etc.
    let status: String         // "success", "pending", "refund"
    let in: [MidgardTransaction]
    let out: [MidgardTransaction]
    let date: String
    let height: String
    let metadata: MidgardActionMetadata?
}

struct MidgardActionMetadata {
    let refund: RefundMetadata?
    let failed: FailedMetadata?
}

struct RefundMetadata {
    let reason: String?
    let code: Int?
    let memo: String?
    let networkFees: [MidgardCoin]?
}

struct FailedMetadata {
    let reason: String?
    let code: Int?
    let memo: String?
}
```

## Example Failure Message Construction

For a refunded transaction:

```
Transaction refunded, Reason: insufficient funds, Code: 108, Memo: swap:BTC.BTC:bc1q...
```

Built from:
- Base: "Transaction refunded"
- Reason: `metadata.refund.reason` or `metadata.failed.reason`
- Code: `metadata.refund.code` or `metadata.failed.code`
- Memo: `metadata.failed.memo`

## Error Handling

### HTTP Status Codes

| HTTP Status | App Status | Description |
|-------------|------------|-------------|
| 200 with empty actions | `.notFound` | Transaction not indexed yet |
| 404 | `.notFound` | Transaction doesn't exist |
| 429 | `.failed(reason: "Rate limited")` | Too many requests |
| 5xx | `.failed(reason: "Server error (retryable)")` | Server error |
| Timeout | `.failed(reason: "Request timeout (retryable)")` | Network timeout |
| Network Error | `.failed(reason: "Network error (retryable)")` | Connection issue |

## Implementation Files

- **API**: `THORChainTransactionStatusAPI.swift`
- **Models**: `THORChainTransactionStatusResponse.swift`
- **Provider**: `THORChainTransactionStatusProvider.swift`
- **Endpoints**: `Endpoint.swift` (thorchainMidgard, mayachainMidgard)

## Notes

1. The first action in the `actions` array is used for status determination
2. Block height is extracted from `action.height` and parsed as an integer
3. Unknown status values default to `.pending` for safety
4. The provider handles both THORChain (mainnet/stagenet) and MayaChain
