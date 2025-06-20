# Vultisig Security/Fraud Detection System

## Overview

This document describes the newly implemented security and fraud detection system for the Vultisig app, which replaces the previously removed Blowfish integration with a more generic, protocol-based approach.

## Architecture

### Core Components

1. **SecurityProvider Protocol** - Defines the interface for security providers
2. **SecurityService** - Main service that manages multiple providers  
3. **SecurityScanViewModel** - SwiftUI view model for handling scan state
4. **SecurityScanView** - SwiftUI component for displaying scan results

### Supported Providers

- **Blockaid** - Production security provider with comprehensive blockchain security features
  - EVM JSON-RPC transaction scanning (`/evm/json-rpc/scan`)
  - EVM raw transaction scanning (`/evm/transaction/scan`)
  - Solana message scanning (`/solana/message/scan`)
  - Token risk assessment (`/token/scan`)
  - Address validation (`/evm/address/scan`, `/solana/address/scan`)
  - Website/dApp scanning (`/site/scan`)
- **Mock Provider** - Development/testing provider that simulates responses

## Features

### Transaction Security Scanning

- **Multi-chain Support**: EVM chains (Ethereum, Polygon, BSC, etc.) and Solana
- **Transaction Type Detection**: Transfer, swap, contract interaction, etc.
- **Risk Level Assessment**: Low, Medium, High, Critical
- **Warning Classifications**: Suspicious contracts, phishing, high-value transfers, etc.
- **Recommendations**: Actionable advice for users

### Integration Points

The security scanning is integrated into key user flows:

- **Keysign Verification**: Before signing transactions
- **Send Transaction Verification**: During the send flow
- **Swap Confirmation**: Before executing swaps

## Usage

### Basic Implementation

```swift
// Create a security scan request
let request = SecurityScanRequest(
    chain: .ethereum,
    transactionType: .transfer,
    fromAddress: "0x...",
    toAddress: "0x...",
    amount: "1000000000000000000"
)

// Scan the transaction
let response = try await SecurityService.shared.scanTransaction(request)

// Check results
if response.hasWarnings {
    print("Warnings: \(response.warningMessages)")
}
```

### SwiftUI Integration

```swift
struct TransactionView: View {
    @StateObject private var securityViewModel = SecurityScanViewModel()
    
    var body: some View {
        VStack {
            // Your transaction UI
            
            SecurityScanView(viewModel: securityViewModel)
        }
        .task {
            await securityViewModel.scanTransaction(from: transaction)
        }
    }
}
```

## Configuration

### Environment-based Configuration

The system automatically configures based on build configuration:

- **Debug builds**: Use mock provider with simulated warnings
- **Release builds**: Use Blockaid provider with optional API key

### Manual Configuration

```swift
let config = SecurityServiceFactory.Configuration(
    useBlockaid: true,
    useMockProvider: false,
    mockProviderSimulateWarnings: false,
    isEnabled: true
)

SecurityServiceFactory.configure(with: config)
```

### Proxy Architecture

Vultisig uses a proxy architecture for security scanning to protect API credentials:

- **Client**: Makes requests to `https://api.vultisig.com/blockaid/v0/*`
- **Vultisig Proxy**: Forwards requests to `https://api.blockaid.io/v0/*` with proper authentication
- **Blockaid API**: Processes security scan requests and returns results

This approach ensures:
- ✅ API keys remain secure on the server
- ✅ No sensitive credentials in the mobile app
- ✅ Centralized rate limiting and monitoring
- ✅ Easy provider switching without app updates

### Backend Proxy Implementation

To implement the Blockaid proxy on your backend, you'll need to handle these endpoints:

```javascript
// Example proxy endpoints (Node.js/Express)
app.post('/blockaid/v0/evm/json-rpc/scan', async (req, res) => {
  const response = await fetch('https://api.blockaid.io/v0/evm/json-rpc/scan', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${process.env.BLOCKAID_API_KEY}`
    },
    body: JSON.stringify(req.body)
  });
  
  const data = await response.json();
  res.json(data);
});

app.post('/blockaid/v0/solana/message/scan', async (req, res) => {
  // Similar implementation for Solana scanning
});

app.post('/blockaid/v0/token/scan', async (req, res) => {
  // Similar implementation for token scanning
});

app.post('/blockaid/v0/evm/address/scan', async (req, res) => {
  // Similar implementation for address validation
});
```

Required endpoints to implement:
- `POST /blockaid/v0/evm/json-rpc/scan`
- `POST /blockaid/v0/evm/transaction/scan`
- `POST /blockaid/v0/solana/message/scan`
- `POST /blockaid/v0/token/scan`
- `POST /blockaid/v0/evm/address/scan`
- `POST /blockaid/v0/site/scan`

### User Preferences

Users can control security scanning through UserDefaults:

```swift
// Disable security scanning
UserDefaults.standard.setSecurityScanEnabled(false)

// Disable specific provider
UserDefaults.standard.setBlockaidEnabled(false)
```

## API Integration

### Blockaid Integration

The Blockaid provider integrates with the Blockaid API v0 (2025) through the Vultisig proxy:

- **Base URL**: `https://api.vultisig.com/blockaid/v0` (proxied)
- **EVM JSON-RPC Endpoint**: `/evm/json-rpc/scan`
- **EVM Transaction Endpoint**: `/evm/transaction/scan`
- **Solana Message Endpoint**: `/solana/message/scan`
- **Token Scan Endpoint**: `/token/scan`
- **Address Validation**: `/evm/address/scan`, `/solana/address/scan`
- **Authentication**: Handled by Vultisig proxy (API key not exposed to client)

### Request/Response Format

#### EVM JSON-RPC Scanning
```swift
// Request
{
    "chain": "ethereum",
    "data": {
        "method": "eth_sendTransaction",
        "params": [{
            "from": "0x...",
            "to": "0x...",
            "value": "0x...",
            "data": "0x..."
        }]
    },
    "metadata": {
        "domain": "vultisig.com"
    }
}
```

#### Solana Message Scanning
```swift
// Request
{
    "chain": "solana",
    "data": {
        "message": "base64_encoded_message",
        "account_address": "wallet_address"
    },
    "metadata": {
        "domain": "vultisig.com"
    }
}
```

#### Response Format
```swift
// Response  
{
    "request_id": "abc123",
    "validation": {
        "classification": "warning",
        "result_type": "malicious",
        "features": [
            {
                "type": "suspicious_contract",
                "severity": "medium",
                "description": "Contract has limited verification",
                "address": "0x..."
            }
        ]
    }
}
```

## Security Considerations

1. **Privacy**: Transaction data is sent to third-party providers for analysis
2. **Availability**: Graceful fallback when providers are unavailable
3. **Rate Limiting**: Providers may have rate limits
4. **API Keys**: Securely manage provider API credentials

## Error Handling

The system includes comprehensive error handling:

- Network connectivity issues
- Provider API errors  
- Rate limiting
- Invalid responses
- Chain not supported

Errors are logged and displayed to users appropriately.

## Testing

### Testing with Real Blockaid

For development and testing, use the real Blockaid provider through the proxy:

```swift
// SecurityService will use Blockaid provider by default
let response = try await SecurityService.shared.scanTransaction(request)
// This will make real calls to Blockaid through the Vultisig proxy
```

### Unit Tests

Test security scanning with different scenarios:

```swift
func testHighRiskTransaction() async throws {
    let request = SecurityScanRequest(/* high-risk parameters */)
    let response = try await provider.scanTransaction(request)
    XCTAssertEqual(response.riskLevel, .high)
    XCTAssertTrue(response.hasWarnings)
}
```

## Future Enhancements

1. **Additional Providers**: Support for more security providers
2. **Offline Detection**: Local pattern matching for known threats
3. **User Feedback**: Allow users to report false positives/negatives
4. **Analytics**: Track security scan effectiveness
5. **Custom Rules**: User-defined security rules and thresholds

## Migration from Blowfish

This system provides a drop-in replacement for the removed Blowfish integration with these improvements:

- **Provider Agnostic**: Easy to add/remove providers
- **Better Error Handling**: More robust error management
- **Enhanced UI**: Improved user experience with detailed warnings
- **Configuration**: Flexible configuration options
- **Testing**: Built-in mock provider for development

The API surface is designed to be similar to the original Blowfish integration to minimize migration effort. 