# THORChain Deposits Integration

## Overview
Implement support for displaying RUJI Deposits. The feature adds a new "Deposits" section to the asset page showing the deposit balance. Users can withdraw deposits through a new "RUJI Unmerge" FUNCTION call.

## Implementation

### New Files

1. **DepositService.swift** - Service for fetching RUJI deposits
```swift
func fetchDeposits(for thorAddress: String) async -> DepositBalance {
    // 1. Convert THORChain address to base64-encoded ID
    let accountID = "Account:\(thorAddress)"
    let base64ID = Data(accountID.utf8).base64EncodedString()
    
    // 2. Execute GraphQL query to fetch deposit data
    // Query format:
    /*
    {
      node(id:"QWNjb3VudDp0aG9yMWEzeGZxeDR5dDR5aHltaG0yMm0zNmh1dWgzZWtsZjQ5Z3p0eXZq") {
        ... on Account {
          merge {
            accounts {
              pool {
                mergeAsset {
                  metadata {
                    symbol
                  }
                }
              }
              size {
                amount
              }
              shares
            }
          }
        }
      }
    }
    */
    // 3. Parse response and sum all shares
    // 4. Return DepositBalance with totalShares and estimatedValue
}

// Note: Withdrawal functionality is handled through the FUNCTION call system with "RUJI Unmerge"
```

2. **DepositBalanceView.swift** - UI component showing RUJI deposits in Deposits section
```swift
struct DepositBalanceView: View {
    @ObservedObject var vault: Vault
    @State private var depositBalance: DepositBalance?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Deposits")
            // Display deposit balance
        }
        .onAppear {
            loadDeposits()
        }
    }
}
```

// Note: No separate withdrawal view needed as withdrawal is handled through FUNCTION calls

### Modified Files

1. **VaultDetailView.swift** - Add RUJIBalanceView below balance section
```swift
var view: some View {
    List {
        headerContent
        balanceContent
        DepositBalanceView(vault: vault) // Add new Deposits view here
        // Existing views continue...
    }
}
```

## Code Flow

1. **Data Fetching:**
   - On asset page load, `DepositBalanceView` calls `DepositService.fetchDeposits()`
   - Service executes GraphQL query with base64-encoded THORChain address
   - Response is parsed to extract share amounts and symbols
   - Total shares are summed across all assets with 8 decimal places

2. **Withdrawal Process:**
   - User selects "RUJI Unmerge" from FUNCTION calls
   - User enters amount to withdraw
   - System calculates estimated receive amount using formula: min(size * amount / shares)
   - On submission, a MsgExecuteContract is created with withdraw amount to contract thorchain1dheycdevq39qlkxs2a6wuuzyn4aqxhve3hhmlw
   - Transaction is signed and broadcast to THORChain

## Checklist

- [ ] Implement proper share summation with 8 decimal places
- [ ] Create DepositBalanceView component for Deposits section
- [ ] Ensure "RUJI Unmerge" function call creates proper MsgExecuteContract with withdraw amount to thorchain1dheycdevq39qlkxs2a6wuuzyn4aqxhve3hhmlw
- [ ] Add DepositBalanceView to VaultDetailView
- [ ] Test deposit balance display with real THORChain accounts
- [ ] Test withdrawal functionality with small amounts
- [ ] Add error handling for failed API requests or transactions