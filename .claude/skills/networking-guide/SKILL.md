---
name: networking-guide
description: HTTP networking layer reference — TargetType, HTTPClient, services, error handling.
user-invocable: false
---

# Networking Guide

## Core HTTP Layer

All networking uses a custom HTTP client built on `URLSession` with async/await.

**Key files (all under `VultisigApp/VultisigApp/Services/Network/`):**

| File | Purpose |
|------|---------|
| `TargetType.swift` | Endpoint definition protocol + HTTPTask + ParameterEncoding + ValidationType |
| `HTTPClient.swift` | URLSession wrapper implementation |
| `HTTPClientProtocol.swift` | Protocol for dependency injection |
| `HTTPError.swift` | Error types + HTTPResponse struct |
| `HTTPMethod.swift` | HTTP methods enum |

---

## TargetType Protocol

```swift
public protocol TargetType {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var task: HTTPTask { get }
    var headers: [String: String]? { get }
    var validationType: ValidationType { get }   // default: .successCodes
    var timeoutInterval: TimeInterval { get }    // default: 60.0
}

// Default header: ["Content-Type": "application/json"]
```

## HTTPTask Enum

```swift
public enum HTTPTask {
    case requestPlain                                              // No parameters
    case requestParameters([String: Any], ParameterEncoding)       // Dictionary params
    case requestData(Data)                                         // Raw data body
    case requestCompositeData(bodyData: Data, urlParameters: [String: Any])  // Body + URL params
    case requestCodable(Encodable, ParameterEncoding)              // Codable object
}
```

## ParameterEncoding

```swift
public enum ParameterEncoding {
    case urlEncoding    // Query parameters (GET requests)
    case jsonEncoding   // JSON body (POST/PUT/PATCH)
    case formEncoding   // Form data (application/x-www-form-urlencoded)
}
```

## ValidationType

```swift
public enum ValidationType {
    case noValidation
    case successCodes          // 200-299 (default)
    case customCodes([Int])
}
```

## HTTPMethod

```swift
public enum HTTPMethod: String, CaseIterable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}
```

## HTTPClientProtocol

```swift
protocol HTTPClientProtocol {
    func request(_ target: TargetType) async throws -> HTTPResponse<Data>
    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T>
    func requestEmpty(_ target: TargetType) async throws -> HTTPResponse<EmptyResponse>
}
```

## HTTPError

```swift
enum HTTPError: Error, LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case statusCode(Int, Data?)
    case encodingFailed
    case decodingFailed(Error)
    case networkError(Error)
    case timeout
    case invalidSSLCertificate
}

struct HTTPResponse<T> {
    let data: T
    let response: HTTPURLResponse
}
```

---

## Creating API Endpoints

Define endpoints as a `TargetType` enum:

```swift
// Services/[Feature]/[Feature]API.swift
enum MyFeatureAPI: TargetType {
    case getData(id: String)
    case postData(payload: MyPayload)

    var baseURL: URL {
        URL(string: "https://api.example.com")!
    }

    var path: String {
        switch self {
        case .getData(let id): return "/data/\(id)"
        case .postData: return "/data"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getData: return .get
        case .postData: return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getData: return .requestPlain
        case .postData(let payload): return .requestCodable(payload, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["X-Client-ID": "vultisig"]
    }
}
```

## Creating Services

Services use constructor injection:

```swift
// Services/[Feature]/[Feature]Service.swift
struct MyFeatureService {
    let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getData(id: String) async throws -> MyModel {
        let response = try await httpClient.request(
            MyFeatureAPI.getData(id: id),
            responseType: MyModel.self
        )
        return response.data
    }
}
```

## Error Handling

Use domain-specific error enums:

```swift
enum MyFeatureError: Error, LocalizedError {
    case notFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound: return "Resource not found"
        case .invalidData: return "Invalid data received"
        }
    }
}
```

---

## Real-World Examples

### THORChainAPI (GET-only, plain requests)

**File:** `Services/THORChainAPI/TargetType/THORChainAPI.swift`

```swift
enum THORChainAPI: TargetType {
    case getThornameDetails(name: String)
    case getPools
    case getPoolAsset(asset: String)
    case getLastBlock
    case getNetworkFees
    case getConstants
    // ...

    var baseURL: URL {
        switch self {
        case .getThornameDetails, .getPools, .getPoolAsset, .getLastBlock, .getNetworkFees, .getConstants:
            return URL(string: "https://thornode.ninerealms.com/thorchain")!
        case .getThornameLookup, .getAddressLookup, .getHealth, .getNetworkInfo:
            return URL(string: "https://midgard.ninerealms.com")!
        }
    }

    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
}
```

**Service:** `Services/THORChainAPI/THORChainAPIService.swift`

```swift
struct THORChainAPIService {
    let httpClient: HTTPClientProtocol
    let cache = THORChainAPICache()

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getPools() async throws -> [THORChainPoolResponse] {
        if let cached = await cache.getCachedPools() { return cached }
        let response = try await httpClient.request(
            THORChainAPI.getPools,
            responseType: [THORChainPoolResponse].self
        )
        await cache.cachePools(response.data)
        return response.data
    }
}
```

### TronAPI (Mixed GET/POST, multiple HTTPTask variants)

**File:** `Services/Tron/TronAPI.swift`

```swift
enum TronAPI: TargetType {
    case getNowBlock
    case getAccount(address: String)
    case broadcastTransaction(jsonString: String)
    case triggerConstantContract(ownerAddress: String, contractAddress: String,
                                functionSelector: String, parameter: String)

    var method: HTTPMethod {
        switch self {
        case .getNowBlock, .getChainParameters: return .get
        case .getAccount, .broadcastTransaction, .triggerConstantContract: return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getNowBlock: return .requestPlain
        case .getAccount(let address):
            return .requestParameters(["address": address, "visible": true], .jsonEncoding)
        case .broadcastTransaction(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return .requestPlain }
            return .requestData(data)
        case .triggerConstantContract(let owner, let contract, let selector, let param):
            return .requestParameters([
                "owner_address": owner, "contract_address": contract,
                "function_selector": selector, "parameter": param, "visible": true
            ], .jsonEncoding)
        }
    }
}
```

---

## Caching Pattern

```swift
actor MyCache {
    private var cachedData: [Item]?
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 300

    func getCachedData() -> [Item]? {
        guard let data = cachedData, let lastFetch,
              Date().timeIntervalSince(lastFetch) < cacheDuration
        else { return nil }
        return data
    }

    func cacheData(_ data: [Item]) {
        cachedData = data
        lastFetch = Date()
    }
}
```

**Reference:** `Services/THORChainAPI/THORChainAPICache.swift`
