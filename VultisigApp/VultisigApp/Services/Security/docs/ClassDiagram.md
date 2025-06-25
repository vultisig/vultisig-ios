## Architecture Layers:

### 1. **Service Layer** (Core Logic)
- **SecurityService** - Main singleton managing security operations
- **SecurityProvider** - Protocol for security providers
- **BlockaidProvider** - Concrete implementation

### 2. **View Model Layer** (Business Logic & State)
- **SecurityScanViewModel** - Main VM handling security scans and UI state
- **SendCryptoVerifyViewModel** - VM for send crypto verification
- **JoinKeysignViewModel** - VM for keysign operations

### 3. **View Layer** (UI Components)
- **SecurityScanView** - Main security scan display component
- **CompactSecurityScanView** - Compact version for limited space
- **SecurityRiskBadge** - Badge displaying risk level
- **SendCryptoVerifyView** - Send transaction verification screen
- **KeysignMessageConfirmView** - Keysign confirmation screen
- **WarningView** - Generic warning display

### 4. **Model Layer** (Data Structures)
- Request/Response models (SecurityScanRequest, SecurityScanResponse)
- Domain models (KeysignPayload, SendTransaction, Chain)
- Enumerations for type safety

## Key Relationships:

1. **View Models use SecurityService** - The VMs delegate security operations to the service
2. **Views observe View Models** - SwiftUI's @ObservableObject pattern
3. **SecurityService manages providers** - Plugin architecture for multiple providers
4. **Domain models integrate** - KeysignPayload and SendTransaction are converted to SecurityScanRequest

The architecture follows MVVM pattern with clean separation of concerns, making it easy to add new security providers or UI components.

## Class Diagram

```mermaid
classDiagram
    %% Core Service Layer
    class SecurityService {
        -shared: SecurityService
        -logger: Logger
        -providers: SecurityProvider[]
        -isEnabled: Bool
        +setEnabled(enabled: Bool)
        +addProvider(provider: SecurityProvider)
        +removeProvider(named: String)
        +getProviders(): SecurityProvider[]
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +scanToken(tokenAddress: String, chain: Chain): SecurityScanResponse
        +validateAddress(address: String, chain: Chain): SecurityScanResponse
        +createSecurityScanRequest(from: KeysignPayload): SecurityScanRequest
        +createSecurityScanRequest(from: SendTransaction): SecurityScanRequest
    }

    %% View Models
    class SecurityScanViewModel {
        <<ObservableObject>>
        -securityService: SecurityService
        +isScanning: Bool
        +scanResponse: SecurityScanResponse?
        +errorMessage: String?
        +showAlert: Bool
        +hasResponse: Bool
        +hasWarnings: Bool
        +isSecure: Bool
        +riskLevel: SecurityRiskLevel
        +backgroundColor: Color
        +borderColor: Color
        +iconName: String
        +iconColor: Color
        +scanTransaction(from: KeysignPayload): async
        +scanTransaction(from: SendTransaction): async
        +scanToken(address: String, chain: Chain): async
        +validateAddress(address: String, chain: Chain): async
        +resetScan()
        +getScanSummary(): String
        +getHighRiskAlert(): Alert?
    }

    class SendCryptoVerifyViewModel {
        <<ObservableObject>>
        +isAddressCorrect: Bool
        +isAmountCorrect: Bool
        +isHackedOrPhished: Bool
        +showAlert: Bool
        +isLoading: Bool
        +errorMessage: String
        +securityScanViewModel: SecurityScanViewModel
        +showSecurityScan: Bool
        +performSecurityScan(tx: SendTransaction): async
    }

    class JoinKeysignViewModel {
        <<ObservableObject>>
        +keysignPayload: KeysignPayload?
        +securityScanViewModel: SecurityScanViewModel
        +showSecurityScan: Bool
        +performSecurityScan(): async
    }

    %% Views
    class SecurityScanView {
        <<View>>
        +viewModel: SecurityScanViewModel
        -isExpanded: Bool
        +body: View
        -scanResultView: View
        -scanningView: View
        -icon: View
        -mainContent: View
        -warningsSection: View
        -recommendationsSection: View
    }

    class SecurityRiskBadge {
        <<View>>
        +riskLevel: SecurityRiskLevel
        +body: View
        -badgeColor: Color
    }

    class CompactSecurityScanView {
        <<View>>
        +viewModel: SecurityScanViewModel
        +body: View
    }

    class SendCryptoVerifyView {
        <<View>>
        +sendCryptoViewModel: SendCryptoViewModel
        +sendCryptoVerifyViewModel: SendCryptoVerifyViewModel
        +tx: SendTransaction
        +vault: Vault
        +body: View
    }

    class KeysignMessageConfirmView {
        <<View>>
        +viewModel: JoinKeysignViewModel
        +body: View
    }

    class WarningView {
        <<View>>
        +text: String
        +body: View
    }

    %% Service Layer - Providers
    class SecurityProvider {
        <<interface>>
        +providerName: String
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +supportsChain(chain: Chain): Bool
    }

    class BlockaidProvider {
        +capabilities: SecurityProviderCapabilities
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +validateAddress(address: String, chain: Chain): SecurityScanResponse
        +scanToken(tokenAddress: String, chain: Chain): SecurityScanResponse
    }

    %% Models
    class SecurityScanRequest {
        +chain: Chain
        +transactionType: SecurityTransactionType
        +fromAddress: String
        +toAddress: String
        +amount: String?
        +data: String?
        +metadata: Dictionary
    }

    class SecurityScanResponse {
        +provider: String
        +isSecure: Bool
        +riskLevel: SecurityRiskLevel
        +warnings: SecurityWarning[]
        +recommendations: String[]
        +hasWarnings: Bool
        +warningMessages: String[]
    }

    class SecurityWarning {
        +type: SecurityWarningType
        +severity: SecuritySeverity
        +message: String
        +details: String?
    }

    %% Domain Models
    class KeysignPayload {
        +coin: Coin
        +toAddress: String
        +toAmount: BigInt
        +memo: String?
        +chainSpecific: String
    }

    class SendTransaction {
        +coin: Coin
        +fromAddress: String
        +toAddress: String
        +amount: String
        +memo: String
        +gas: BigInt
    }

    class Chain {
        +name: String
        +chainType: ChainType
    }

    %% Enumerations
    class SecurityRiskLevel {
        <<enumeration>>
        +none
        +low
        +medium
        +high
        +critical
        +displayName: String
    }

    class SecurityWarningType {
        <<enumeration>>
        +suspiciousContract
        +highValueTransfer
        +maliciousContract
        +phishingAttempt
        +other
    }

    class SecuritySeverity {
        <<enumeration>>
        +info
        +warning
        +error
        +critical
    }

    %% Relationships - Service Layer
    SecurityService "1" --> "*" SecurityProvider : manages
    SecurityService ..> SecurityScanRequest : creates
    SecurityService ..> SecurityScanResponse : returns
    SecurityProvider <|.. BlockaidProvider : implements
    
    %% Relationships - View Models
    SecurityScanViewModel --> SecurityService : uses
    SecurityScanViewModel --> SecurityScanResponse : displays
    SendCryptoVerifyViewModel --> SecurityScanViewModel : contains
    JoinKeysignViewModel --> SecurityScanViewModel : contains
    
    %% Relationships - Views to View Models
    SecurityScanView --> SecurityScanViewModel : observes
    SendCryptoVerifyView --> SendCryptoVerifyViewModel : observes
    KeysignMessageConfirmView --> JoinKeysignViewModel : observes
    CompactSecurityScanView --> SecurityScanViewModel : observes
    SecurityRiskBadge --> SecurityRiskLevel : displays
    
    %% Relationships - Domain Integration
    SecurityService ..> KeysignPayload : converts to request
    SecurityService ..> SendTransaction : converts to request
    SecurityScanRequest --> Chain : references
    KeysignPayload --> Chain : has
    SendTransaction --> Chain : has
    
    %% Relationships - Response Models
    SecurityScanResponse "1" --> "*" SecurityWarning : contains
    SecurityScanResponse --> SecurityRiskLevel : has
    SecurityWarning --> SecurityWarningType : has
    SecurityWarning --> SecuritySeverity : has
```
