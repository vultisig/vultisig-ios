//
//  HTTPError.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation

/// HTTP networking errors
public enum HTTPError: Error, LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case statusCode(Int, Data?)
    case encodingFailed
    case decodingFailed(Error)
    case networkError(Error)
    case timeout
    case invalidSSLCertificate
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .invalidResponse:
            return "Invalid response"
        case .statusCode(let code, _):
            return "HTTP status code: \(code)"
        case .encodingFailed:
            return "Failed to encode parameters"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timeout"
        case .invalidSSLCertificate:
            return "Invalid SSL certificate"
        }
    }
}

/// HTTP response model
public struct HTTPResponse<T> {
    public let data: T
    public let response: HTTPURLResponse
    
    public init(data: T, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

/// Empty response type for requests that don't return data
public struct EmptyResponse: Codable {
    public init() {}
}
