import Foundation
import WalletCore

// Define the structures for responses and interfaces
struct TonAddressInformation: Codable {
    var balance: String
    var code: String
    var data: String
    var frozen_hash: String
    var last_transaction_hash: String
    var last_transaction_lt: String
    var status: String
}

struct ApiResponse<T: Codable>: Codable {
    let ok: Bool
    let result: T?
    let error: String?
    let code: Int?
}

// MARK: - TonAPI Codable models
struct TonApiJettonBalanceResponse: Codable {
    let balances: [TonApiJettonBalanceItem]
}
struct TonApiJettonBalanceItem: Codable {
    let balance: String
    let wallet_address: TonApiAddressRef?
    let wallet: TonApiAddressRef?
    let jetton: TonApiJettonInfo
}
struct TonApiAddressRef: Codable {
    let address: String
}
struct TonApiJettonInfo: Codable {
    let address: String
    let name: String?
    let symbol: String?
    let decimals: Int?
}
struct TonApiJettonWalletsResponse: Codable {
    let wallets: [TonApiWalletItem]?
    let address: String?
}
struct TonApiWalletItem: Codable {
    let address: String
}

struct ResultData: Codable {
    struct AddressInfo: Codable {
        let type = "accountAddress"
        let account_address: String
        enum CodingKeys: CodingKey {
            case account_address
        }
    }
    
    struct LastTransactionIdInfo: Codable {
        let type = "internal.transactionId"
        let lt: String
        let hash: String
        enum CodingKeys: CodingKey {
            case lt
            case hash
        }
    }
    
    struct BlockIdInfo: Codable {
        let type = "ton.blockIdExt"
        let workchain: Int
        let shard: String
        let seqno: Int
        let root_hash: String
        let file_hash: String
        enum CodingKeys: CodingKey {
            case workchain
            case shard
            case seqno
            case root_hash
            case file_hash
        }
    }
    
    struct AccountStateInfo: Codable {
        let type = "wallet.v4.accountState"
        let wallet_id: String
        let seqno: Int
        enum CodingKeys: CodingKey {
            case wallet_id
            case seqno
        }
    }
    
    var type = "fullAccountState"
    var address: AddressInfo
    var balance: String
    var last_transaction_id: LastTransactionIdInfo
    var block_id: BlockIdInfo
    var sync_utime: Int
    var account_state: AccountStateInfo
    var revision: Int
    let extra: String
}

struct TonBroadcastSuccessResponse: Codable {
    let hash: String
}

class TonService {
    
    static let shared = TonService()
    
    func broadcastTransaction(_ obj: String) async throws -> String {
        
        let body: [String: Any] = ["boc": obj]
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        guard let url = URL(string: Endpoint.broadcastTonTransaction()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = dataPayload
        let (data,response) = try await URLSession.shared.data(for: request)
        print("Ton broadcast response: \(String(data: data, encoding: .utf8) ?? "")")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            let result = try JSONDecoder().decode(ApiResponse<TonBroadcastSuccessResponse>.self, from: data)
            return result.result?.hash ?? ""
        case 500:
            let result = try JSONDecoder().decode(ApiResponse<String>.self, from: data)
            let duplicate = result.error?.contains("duplicate message") ?? false
            if duplicate {
                return ""
            } else {
                throw NSError(domain: "Server Error", code: 500, userInfo: [NSLocalizedDescriptionKey: result.error ?? "Unknown server error"])
            }
        default:
            throw NSError(domain: "Unexpected response code", code: httpResponse.statusCode, userInfo: nil)
        }
    }
    
    func getBalance(_ coin: Coin) async throws -> String {
        
        guard let url = URL(string: Endpoint.fetchTonBalance(address: coin.address)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let balance = Utils.extractResultFromJson(fromData: data, path: "balance") as? String {
            return balance
        }
        
        return .zero
    }
    
    func getJettonBalance(_ coin: Coin) async throws -> String {
        guard let url = URL(string: Endpoint.fetchTonJettonBalance(address: coin.address, jettonAddress: coin.contractAddress)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors (404, 500, etc.)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            return String.zero
        }
        
        if let decoded = try? JSONDecoder().decode(TonApiJettonBalanceResponse.self, from: data) {
            for item in decoded.balances {
                let apiAddress = item.jetton.address
                let coinAddress = coin.contractAddress
                
                // Normalize both to bounceable format for comparison
                let normalizedApi = TONAddressConverter.toUserFriendly(address: apiAddress, bounceable: true, testnet: false) ?? apiAddress
                let normalizedCoin = TONAddressConverter.toUserFriendly(address: coinAddress, bounceable: true, testnet: false) ?? coinAddress
                
                if normalizedApi == normalizedCoin {
                    return item.balance
                }
            }
        }
        return String.zero
    }
    
    func getSpecificTransactionInfo(_ coin: Coin) async throws -> (UInt64, UInt64) {
        
        let now = Date()
        let futureDate = now.addingTimeInterval(600)
        let expireAt = UInt64(futureDate.timeIntervalSince1970)
        
        
        guard let url = URL(string: Endpoint.fetchExtendedAddressInformation(address: coin.address)) else {
            throw URLError(.badURL)
        }
        
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        var seqno = UInt64(0)
        if let rseqno = Utils.extractResultFromJson(fromData: data, path: "result.account_state.seqno") as? UInt64 {
            seqno = rseqno
        } else if let rseqnoString = Utils.extractResultFromJson(fromData: data, path: "result.account_state.seqno") as? String {
            seqno = UInt64(rseqnoString) ?? 0
        }
        
        return (seqno, expireAt)
    }
    
    func getWalletState(_ address: String) async throws -> String {
        guard let url = URL(string: Endpoint.fetchTonBalance(address: address)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let status = Utils.extractResultFromJson(fromData: data, path: "status") as? String {
            return status
        }
        
        return "uninit" // Default to uninitialized if status not found
    }
    
    // Synchronous resolver for jetton wallet address (owner + master)
    // Primary: TonAPI v2 /jettons/wallets?owner=&jetton= (deterministic)
    // Secondary: TonAPI v2 /accounts/{owner}/jettons (fallback by matching master)
    // Returns bounceable address when possible
    func getJettonWalletAddressSync(ownerAddress: String, masterAddress: String, timeout: TimeInterval = 8.0) -> String? {
        func toBounceable(_ addr: String?) -> String? {
            guard let addr else { return nil }
            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resolved: String? = nil

        // 1) Dedicated wallets endpoint (owner)
        if let url = URL(string: Endpoint.tonApiJettonWallets(owner: ownerAddress, jetton: masterAddress)) {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let task = URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { semaphore.signal() }
                guard let data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Try common shapes: {"wallets":[{"address":"..."}]} or {"address":"..."}
                    if let wallets = json["wallets"] as? [[String: Any]] {
                        if let first = wallets.first, let addr = first["address"] as? String {
                            resolved = addr
                            return
                        }
                    }
                    if let addr = json["address"] as? String {
                        resolved = addr
                        return
                    }
                }
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + timeout)
            if let addr = toBounceable(resolved) { return addr }
        }

        // 1b) Dedicated wallets endpoint (account param variant)
        resolved = nil
        if let url = URL(string: Endpoint.tonApiJettonWalletsAccount(account: ownerAddress, jetton: masterAddress)) {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let task = URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { semaphore.signal() }
                guard let data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let wallets = json["wallets"] as? [[String: Any]] {
                        if let first = wallets.first, let addr = first["address"] as? String {
                            resolved = addr
                            return
                        }
                    }
                    if let addr = json["address"] as? String {
                        resolved = addr
                        return
                    }
                }
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + timeout)
            if let addr = toBounceable(resolved) { return addr }
        }

        // 2) Fallback: accounts/{owner}/jettons
        resolved = nil
        if let url = URL(string: Endpoint.tonApiAccountJettons(owner: ownerAddress)) {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let task = URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { semaphore.signal() }
                guard let data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let balances = json["balances"] as? [[String: Any]] {
                    let normalizedMasterEQ = masterAddress.replacingOccurrences(of: "0:", with: "EQ")
                    let normalizedMasterRaw = masterAddress.replacingOccurrences(of: "EQ", with: "0:")
                    for item in balances {
                        guard let jetton = item["jetton"] as? [String: Any],
                              let jettonAddr = jetton["address"] as? String else { continue }
                        if jettonAddr == masterAddress || jettonAddr == normalizedMasterEQ || jettonAddr == normalizedMasterRaw {
                            if let walletObject = item["wallet_address"] as? [String: Any],
                               let addr = walletObject["address"] as? String {
                                resolved = addr
                                break
                            } else if let addr = item["wallet_address"] as? String {
                                resolved = addr
                                break
                            } else if let wallet = item["wallet"] as? [String: Any],
                                      let addr = wallet["address"] as? String {
                                resolved = addr
                                break
                            }
                        }
                    }
                }
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + timeout)
            if let addr = toBounceable(resolved) { return addr }
        }
        return nil
    }

    // Deterministic fallback using runGetMethod(get_wallet_address)
    // Expects masterAddress (jetton minter) and ownerAddress (TON wallet)
    func getJettonWalletAddressViaRunGetMethodSync(ownerAddress: String, masterAddress: String, timeout: TimeInterval = 8.0) -> String? {
        // Build TON Center-compatible call via Vultisig proxy if available
        // Use master + slice(owner) encoded as BOC, however we can leverage WalletCore helper to convert owner to BOC
        // Prepare stack: [ ["tvm.Slice", toBoc(owner)] ]
        guard let ownerBoc = TONAddressConverter.toBoc(address: ownerAddress) else { return nil }
        let payload: [String: Any] = [
            "address": masterAddress,
            "method": "get_wallet_address",
            "stack": [["tvm.Slice", ownerBoc]]
        ]
        guard let url = URL(string: Endpoint.tonCenterRunGetMethod()) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let semaphore = DispatchSemaphore(value: 0)
        var resolved: String? = nil
        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok,
               let result = json["result"] as? [String: Any] {
                let stackAny = result["stack"]
                // Handle both shapes: [[Any]] or [[String:Any]]
                if let stack = stackAny as? [[Any]] {
                    for entry in stack {
                        if entry.count >= 2 {
                            let value = entry[1]
                            var boc: String?
                            if let s = value as? String { boc = s }
                            else if let dict = value as? [String: Any] {
                                boc = (dict["bytes"] as? String) ?? (dict["b64"] as? String) ?? (dict["boc"] as? String)
                            }
                            if let boc, let addr = TONAddressConverter.fromBoc(boc: boc) {
                                resolved = addr
                                break
                            }
                        }
                    }
                } else if let stack = stackAny as? [[String: Any]] {
                    for item in stack {
                        if let cell = item["value"] as? [String: Any] {
                            let boc = (cell["bytes"] as? String) ?? (cell["b64"] as? String) ?? (cell["boc"] as? String)
                            if let boc, let addr = TONAddressConverter.fromBoc(boc: boc) {
                                resolved = addr
                                break
                            }
                        } else if let boc = item["boc"] as? String, let addr = TONAddressConverter.fromBoc(boc: boc) {
                            resolved = addr
                            break
                        }
                    }
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        if let addr = resolved, let converted = TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) {
            return converted
        }
        return resolved
    }

    // MARK: - Async variants (no semaphores)
    func getJettonWalletAddressAsync(ownerAddress: String, masterAddress: String) async -> String? {
        if let byWallets = await tonApiJettonWallets(owner: ownerAddress, master: masterAddress) { return byWallets }
        if let byAccount = await tonApiJettonWalletsAccount(account: ownerAddress, master: masterAddress) { return byAccount }
        if let byBalances = await tonApiAccountJettons(owner: ownerAddress, master: masterAddress) { return byBalances }
        if let byRunGet = await runGetWalletAddress(owner: ownerAddress, master: masterAddress) { return byRunGet }
        return nil
    }
    private func tonApiJettonWallets(owner: String, master: String) async -> String? {
        guard let url = URL(string: Endpoint.tonApiJettonWallets(owner: owner, jetton: master)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let decoded = try? JSONDecoder().decode(TonApiJettonWalletsResponse.self, from: data) {
                if let first = decoded.wallets?.first?.address ?? decoded.address {
                    return TONAddressConverter.toUserFriendly(address: first, bounceable: true, testnet: false) ?? first
                }
            }
        } catch { }
        return nil
    }
    private func tonApiJettonWalletsAccount(account: String, master: String) async -> String? {
        guard let url = URL(string: Endpoint.tonApiJettonWalletsAccount(account: account, jetton: master)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let decoded = try? JSONDecoder().decode(TonApiJettonWalletsResponse.self, from: data) {
                if let first = decoded.wallets?.first?.address ?? decoded.address {
                    return TONAddressConverter.toUserFriendly(address: first, bounceable: true, testnet: false) ?? first
                }
            }
        } catch { }
        return nil
    }
    private func tonApiAccountJettons(owner: String, master: String) async -> String? {
        guard let url = URL(string: Endpoint.tonApiAccountJettons(owner: owner)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let decoded = try? JSONDecoder().decode(TonApiJettonBalanceResponse.self, from: data) {
                let normalizedMasterEQ = master.replacingOccurrences(of: "0:", with: "EQ")
                let normalizedMasterRaw = master.replacingOccurrences(of: "EQ", with: "0:")
                for item in decoded.balances {
                    let jettonAddr = item.jetton.address
                    if jettonAddr == master || jettonAddr == normalizedMasterEQ || jettonAddr == normalizedMasterRaw {
                        if let addr = item.wallet_address?.address ?? item.wallet?.address {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                    }
                }
            }
        } catch { }
        return nil
    }
    private func runGetWalletAddress(owner: String, master: String) async -> String? {
        guard let boc = TONAddressConverter.toBoc(address: owner) else { return nil }
        let payload: [String: Any] = [
            "address": master,
            "method": "get_wallet_address",
            "stack": [["tvm.Slice", boc]]
        ]
        guard let url = URL(string: Endpoint.tonCenterRunGetMethod()) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok,
               let result = json["result"] as? [String: Any],
               let stackAny = result["stack"] {
                if let stack = stackAny as? [[Any]] {
                    for entry in stack where entry.count >= 2 {
                        let value = entry[1]
                        var blob: String?
                        if let s = value as? String { blob = s }
                        else if let dict = value as? [String: Any] { blob = (dict["bytes"] as? String) ?? (dict["b64"] as? String) ?? (dict["boc"] as? String) }
                        if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                    }
                } else if let stack = stackAny as? [[String: Any]] {
                    for item in stack {
                        if let cell = item["value"] as? [String: Any] {
                            let blob = (cell["bytes"] as? String) ?? (cell["b64"] as? String) ?? (cell["boc"] as? String)
                            if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                            }
                        } else if let blob = item["boc"] as? String, let addr = TONAddressConverter.fromBoc(boc: blob) {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                    }
                }
            }
        } catch { }
        return nil
    }
}
