//
//  MayaChainService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

class MayachainService: ThorchainSwapProvider {
    static let shared = MayachainService()
    
    private init() {}
    
    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        guard let url = URL(string: Endpoint.fetchAccountBalanceMayachain(address: address)) else        {
            return [CosmosBalance]()
        }
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        
        let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
        return balanceResponse.balances
    }
    
    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue? {
        guard let url = URL(string: Endpoint.fetchAccountNumberMayachain(address)) else {
            return nil
        }
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        let accountResponse = try JSONDecoder().decode(THORChainAccountNumberResponse.self, from: data)
        return accountResponse.result.value
    }
    func get9RRequest(url: URL) -> URLRequest{
        var req = URLRequest(url:url)
        req.addValue("vultisig", forHTTPHeaderField: "X-Client-ID")
        return req
    }
    
    func fetchSwapQuotes(address: String, fromAsset: String, toAsset: String, amount: String, interval: Int, isAffiliate: Bool) async throws -> ThorchainSwapQuote {

        let url = Endpoint.fetchSwapQuoteThorchain(
            chain: .maya,
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: String(interval),
            isAffiliate: isAffiliate
        )

        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        
        do {
            let response = try JSONDecoder().decode(ThorchainSwapQuote.self, from: data)
            return response
        } catch {
            let error = try JSONDecoder().decode(ThorchainSwapError.self, from: data)
            throw error
        }
    }
    
    func broadcastTransaction(jsonString: String) async -> Result<String,Error> {
        let url = URL(string: Endpoint.broadcastTransactionMayachain)!
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do{
            let (data,resp)  =  try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid http response"))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("status code:\(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: data)
            // Check if the transaction was successful based on the `code` field
            // code 19 means the transaction has been exist in the mempool , which indicate another party already broadcast successfully
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                // Transaction successful
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: data, encoding: .utf8) ?? "Unknown error"))
            
        }
        catch{
            return .failure(error)
        }
        
    }
    
    static let depositAssets: [String] = [
        "THOR.RUNE",
        "XRD.XRD",
        "BTC.BTC",
        "DASH.DASH",
        "ETH.ETH",
        "KUJI.KUJI",
        "KUJI.USK",
        "ARB.ETH",
        "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548",
        "ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1",
        "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA",
        "ARB.GMX-0XFC5A1A6EB076A2C7AD06ED22C90D7E710E35AD0A",
        "ARB.GNS-0X18C11FD286C5EC11C3B683CAA813B77F5163A122",
        "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E",
        "ARB.LINK-0XF97F4DF75117A78C1A5A0DBB814AF92458539FB4",
        "ARB.PEPE-0X25D887CE7A35172C62FEBFD67A1856F20FAEBB00",
        "ARB.SUSHI-0XD4D42F0B6DEF4CE0383636770EF773390D85C61A",
        "ARB.TGT-0X429FED88F10285E61B12BDF00848315FBDFCC341",
        "ARB.UNI-0XFA7F8980B0F1E64A2062791CC3B0871572F1F7F0",
        "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
        "ARB.USDT-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9",
        "ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F",
        "ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529",
        "ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933",
        "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
        "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
        "ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0"
    ]
}
