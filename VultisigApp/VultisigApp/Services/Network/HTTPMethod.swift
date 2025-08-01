//
//  HTTPMethod.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation

/// HTTP method definitions for REST API requests
public enum HTTPMethod: String, CaseIterable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}
