//
//  PayloadService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 1/11/2024.
//

import Foundation

enum PayloadServiceError: Error {
    case NetworkError(message: String)
}
final class PayloadService {
    internal let serverURL: String
    
    init(serverURL: String) {
        self.serverURL = serverURL
    }
    func getUrl(hash: String) -> String {
        return "\(serverURL)/payload/\(hash)"
    }
    func shouldUploadToRelay(payload: String) -> Bool {
        // when the payload is m
        if payload.lengthOfBytes(using: .utf8) > 2048 {
            return true
        }
        return false
    }
    
    func uploadPayload(payload: String) async throws -> String {
        let hash = payload.sha256()
        let urlStr = getUrl(hash: hash)
        guard let url = URL(string: urlStr) else {
            throw PayloadServiceError.NetworkError(message: "invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload.data(using: .utf8)
        let (_,resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                throw PayloadServiceError.NetworkError(message: "fail to upload payload to relay server")
            }
        }
        return hash
    }
    
    func getPayload(hash: String) async throws -> String {
        let urlStr = getUrl(hash: hash)
        guard let url = URL(string: urlStr) else {
            throw PayloadServiceError.NetworkError(message: "invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data,resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                throw PayloadServiceError.NetworkError(message: "fail to get payload to relay server")
            }
        }
        return String(data: data,encoding: .utf8) ?? ""
    }
}
