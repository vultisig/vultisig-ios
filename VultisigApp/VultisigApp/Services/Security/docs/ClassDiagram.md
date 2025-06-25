```
classDiagram
    %% Core Service
    class SecurityService {
        -shared: SecurityService
        -logger: Logger
        -providers: SecurityProvider[]
        -isEnabled: Bool
        +setEnabled(enabled: Bool)
        +addProvider(provider: SecurityProvider)
        +removeProvider(named: String)
        +getProviders(): SecurityProvider[]
        +getProviders(for: Chain): SecurityProvider[]
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +scanTransactionWithAllProviders(request: SecurityScanRequest): SecurityScanResponse[]
        +scanToken(tokenAddress: String, chain: Chain): SecurityScanResponse
        +validateAddress(address: String, chain: Chain): SecurityScanResponse
        +scanSite(url: String): SecurityScanResponse
        +createSecurityScanRequest(from: KeysignPayload): SecurityScanRequest
        +createSecurityScanRequest(from: SendTransaction): SecurityScanRequest
        +isSecurityScanningAvailable(for: Chain): Bool
        +getProviderSummary(): String
    }

    %% Protocols
    class SecurityProvider {
        <<interface>>
        +providerName: String
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +supportsChain(chain: Chain): Bool
    }

    class CapabilityAwareSecurityProvider {
        <<interface>>
        +capabilities: SecurityProviderCapabilities
    }

    %% Concrete Implementation
    class BlockaidProvider {
        -logger: Logger
        -baseURL: String
        -session: URLSession
        +capabilities: SecurityProviderCapabilities
        +providerName: String
        +supportsChain(chain: Chain): Bool
        +scanTransaction(request: SecurityScanRequest): SecurityScanResponse
        +validateAddress(address: String, chain: Chain): SecurityScanResponse
        +scanToken(tokenAddress: String, chain: Chain): SecurityScanResponse
        +scanSite(url: String): SecurityScanResponse
        -scanEVMTransaction(request: SecurityScanRequest): SecurityScanResponse
        -scanSolanaTransaction(request: SecurityScanRequest): SecurityScanResponse
        -scanBitcoinTransaction(request: SecurityScanRequest): SecurityScanResponse
        -performRequest(url: URL, body: T): R
    }

    %% Factory and Configuration
    class SecurityServiceFactory {
        +configure(configuration: Configuration)
        +getConfigurationFromEnvironment(): Configuration
        -addAvailableProviders(to: SecurityService)
    }

    class Configuration {
        +isEnabled: Bool
        +default: Configuration
        +disabled: Configuration
    }

    class AvailableSecurityProvider {
        <<enumeration>>
        +blockaid
        +isEnabled: Bool
        +capabilities: SecurityProviderCapabilities
        +createProvider(): SecurityProvider?
        +displayName: String
    }

    %% Capabilities
    class SecurityProviderCapabilities {
        +evmTransactionScanning: Bool
        +solanaTransactionScanning: Bool
        +addressValidation: Bool
        +tokenScanning: Bool
        +siteScanning: Bool
        +bitcoinTransactionScanning: Bool
        +starknetTransactionScanning: Bool
        +stellarTransactionScanning: Bool
        +suiTransactionScanning: Bool
        +blockaid: SecurityProviderCapabilities
        +none: SecurityProviderCapabilities
    }

    %% Request/Response Models
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
        +metadata: Dictionary?
        +hasWarnings: Bool
        +warningMessages: String[]
    }

    class SecurityWarning {
        +type: SecurityWarningType
        +severity: SecuritySeverity
        +message: String
        +details: String?
    }

    %% Enumerations
    class SecurityTransactionType {
        <<enumeration>>
        +transfer
        +swap
        +contractInteraction
        +tokenApproval
        +nftTransfer
        +defiInteraction
        +other
    }

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
        +unknownToken
        +phishingAttempt
        +maliciousContract
        +unusualActivity
        +rugPullRisk
        +sandwichAttack
        +frontRunning
        +other
    }

    class SecuritySeverity {
        <<enumeration>>
        +info
        +warning
        +error
        +critical
        +displayName: String
    }

    class SecurityProviderError {
        <<enumeration>>
        +providerNotSupported
        +chainNotSupported
        +networkError
        +apiError
        +invalidRequest
        +rateLimitExceeded
        +unauthorized
        +unsupportedOperation
        +errorDescription: String?
    }

    %% Relationships
    SecurityService "1" --> "*" SecurityProvider : manages
    SecurityService ..> SecurityScanRequest : uses
    SecurityService ..> SecurityScanResponse : returns
    SecurityService ..> SecurityProviderError : throws
    
    SecurityProvider <|-- CapabilityAwareSecurityProvider : extends
    CapabilityAwareSecurityProvider <|.. BlockaidProvider : implements
    
    BlockaidProvider --> SecurityProviderCapabilities : has
    BlockaidProvider ..> SecurityScanRequest : uses
    BlockaidProvider ..> SecurityScanResponse : returns
    
    SecurityServiceFactory --> SecurityService : configures
    SecurityServiceFactory --> Configuration : uses
    SecurityServiceFactory --> AvailableSecurityProvider : uses
    
    AvailableSecurityProvider --> SecurityProvider : creates
    AvailableSecurityProvider --> SecurityProviderCapabilities : provides
    
    SecurityScanResponse "1" --> "*" SecurityWarning : contains
    SecurityScanResponse --> SecurityRiskLevel : has
    
    SecurityWarning --> SecurityWarningType : has
    SecurityWarning --> SecuritySeverity : has
    
    SecurityScanRequest --> SecurityTransactionType : has

```

## Architecture Overview:

1. **SecurityService** - The main singleton service that manages security providers and coordinates security scans

2. **SecurityProvider Protocol** - The base interface that all security providers must implement

3. **CapabilityAwareSecurityProvider** - An extended protocol that adds capability awareness

4. **BlockaidProvider** - The concrete implementation of the Blockaid security provider

5. **SecurityProviderCapabilities** - Defines what features each provider supports (EVM scanning, Solana scanning, token scanning, etc.)

6. **SecurityServiceFactory** - Factory pattern for configuring the security service with providers

7. **Request/Response Models**:
   - SecurityScanRequest - Input for security scans
   - SecurityScanResponse - Output from security scans
   - SecurityWarning - Individual warnings within a response

8. **Enumerations** for type safety:
   - SecurityTransactionType (transfer, swap, etc.)
   - SecurityRiskLevel (none, low, medium, high, critical)
   - SecurityWarningType (malicious contract, phishing, etc.)
   - SecuritySeverity (info, warning, error, critical)
   - SecurityProviderError (various error types)

The architecture follows a clean plugin-based design where new security providers can be easily added by implementing the SecurityProvider protocol and registering them through the AvailableSecurityProvider enum.
