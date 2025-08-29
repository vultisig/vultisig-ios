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
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse TonAPI response format
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let balances = json["balances"] as? [[String: Any]] {
            
            // Find the jetton with matching symbol/name first, then address
            for balanceItem in balances {
                if let jetton = balanceItem["jetton"] as? [String: Any],
                   let jettonAddress = jetton["address"] as? String,
                   let balance = balanceItem["balance"] as? String {
                    
                    // First try to match by symbol for well-known tokens
                    if let symbol = jetton["symbol"] as? String {
                        if coin.ticker == "USDT" && (symbol == "USDT" || symbol == "USD₮") {
                            return balance
                        }
                    }
                    
                    // Fallback to address matching
                    // TON addresses can be in different formats: 0:xxx or EQxxx
                    let normalizedJettonAddress = jettonAddress.replacingOccurrences(of: "0:", with: "EQ")
                    let normalizedCoinAddress = coin.contractAddress.replacingOccurrences(of: "EQ", with: "0:")
                    
                    // Check all combinations
                    if jettonAddress == coin.contractAddress ||
                        jettonAddress == normalizedCoinAddress ||
                        normalizedJettonAddress == coin.contractAddress {
                        return balance
                    }
                }
            }
        }
        
        return .zero
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
}
