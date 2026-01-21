//
//  MoonPaySignature.swift
//  VultisigApp
//
//  Created by Johnny Luo on 16/5/2025.
//
import Foundation
struct MoonPaySignatureResp: Codable {
    let signature: String
}
struct MoonPaySignatureReq: Codable {
    let url: String
}
struct MoonPaySignatureHelper {
    func getSignature(url: String) async -> String {
        do {
            let req = MoonPaySignatureReq(url: url)
            var request = URLRequest(url: Endpoint.moonPaySignatureUrl())
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let result = try JSONEncoder().encode(req)
            request.httpBody = result
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let resp = resp as? HTTPURLResponse, resp.statusCode == 200 {
                let res = try JSONDecoder().decode(MoonPaySignatureResp.self, from: data)
                return res.signature
            }
        } catch {
            print("fail to get moonpay signature \(error)")
        }
        return ""
    }
}
