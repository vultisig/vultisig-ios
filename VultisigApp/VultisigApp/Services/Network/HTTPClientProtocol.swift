//
//  HTTPClientProtocol.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation

/// Protocol defining the HTTP client interface
public protocol HTTPClientProtocol {
    /// Performs a network request and returns raw data
    /// - Parameter target: The target defining the request configuration
    /// - Returns: HTTPResponse containing raw data and HTTP response
    func request(_ target: TargetType) async throws -> HTTPResponse<Data>

    /// Performs a network request and decodes the response to a specified type
    /// - Parameters:
    ///   - target: The target defining the request configuration
    ///   - responseType: The type to decode the response to
    /// - Returns: HTTPResponse containing decoded data and HTTP response
    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T>

    /// Performs a network request without expecting a response body
    /// - Parameter target: The target defining the request configuration
    /// - Returns: HTTPResponse with EmptyResponse and HTTP response
    func requestEmpty(_ target: TargetType) async throws -> HTTPResponse<EmptyResponse>
}

/// Default implementations for HTTPClientProtocol
public extension HTTPClientProtocol {

    // swiftlint:disable:next unused_parameter
    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T> {
        let response = try await request(target)

        do {
            let decodedData = try JSONDecoder().decode(T.self, from: response.data)
            return HTTPResponse(data: decodedData, response: response.response)
        } catch {
            throw HTTPError.decodingFailed(error)
        }
    }

    /// Convenience method for requests without response body
    func requestEmpty(_ target: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        let response = try await request(target)
        return HTTPResponse(data: EmptyResponse(), response: response.response)
    }
}
