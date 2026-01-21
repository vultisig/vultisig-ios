//
//  TargetType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation

/// Parameter encoding types for different HTTP methods
public enum ParameterEncoding {
    case urlEncoding       // For GET requests (query parameters)
    case jsonEncoding      // For POST/PUT/PATCH requests (JSON body)
    case formEncoding      // For form data
}

/// Task type for different request configurations
public enum HTTPTask {
    case requestPlain                                // No parameters
    case requestParameters([String: Any], ParameterEncoding)  // With parameters
    case requestData(Data)                          // Raw data
    case requestCompositeData(bodyData: Data, urlParameters: [String: Any])  // Both body and URL params
    case requestCodable(Encodable, ParameterEncoding)  // With Codable object
}

/// Protocol defining the structure of API endpoints, similar to Moya's TargetType
public protocol TargetType {
    /// The base URL for the API
    var baseURL: URL { get }

    /// The path to be appended to `baseURL` to form the full `URL`
    var path: String { get }

    /// The HTTP method used in the request
    var method: HTTPMethod { get }

    /// The type of HTTP task to be performed
    var task: HTTPTask { get }

    /// The headers to be used in the request
    var headers: [String: String]? { get }

    /// A Boolean value indicating whether the request should validate the HTTPS certificate
    var validationType: ValidationType { get }

    /// The timeout interval for the request
    var timeoutInterval: TimeInterval { get }
}

/// Validation type for SSL certificate validation
public enum ValidationType {
    case none           // No validation
    case successCodes   // Validate success status codes (200-299)
    case customCodes([Int])  // Validate custom status codes
}

/// Default implementations for TargetType
public extension TargetType {
    var validationType: ValidationType {
        return .successCodes
    }

    var timeoutInterval: TimeInterval {
        return 60.0
    }

    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
}
