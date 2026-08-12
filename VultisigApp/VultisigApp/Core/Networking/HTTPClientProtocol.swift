//
//  HTTPClientProtocol.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation
import OSLog

private let logger = Log.app.other

/// Protocol defining the HTTP client interface
protocol HTTPClientProtocol: Sendable {
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
extension HTTPClientProtocol {

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

    /// Issues a request that is safe to repeat, retrying **once** on a timeout.
    ///
    /// For idempotent reads only. Nothing here can tell whether a target is one,
    /// so choosing this method over `request(_:responseType:)` is the caller
    /// asserting it — a broadcast or any other write must not use it.
    ///
    /// Only `HTTPError.timeout` is retried, and only once. The failure this
    /// exists for is specific: a proxy that accepts a request and then holds it
    /// open until something upstream gives up, at which point an immediate
    /// resend succeeds. Every stall observed while diagnosing that behaved this
    /// way, which is why there is no backoff — the wait is the symptom, not
    /// congestion, and sleeping first would just add to it. A status code, a
    /// decode failure or a cancellation propagates untouched: none of them gets
    /// better by being repeated, and a cancellation must not be.
    func requestRetryingTimeout<T: Decodable>(
        _ target: TargetType,
        responseType: T.Type
    ) async throws -> HTTPResponse<T> {
        do {
            return try await request(target, responseType: responseType)
        } catch HTTPError.timeout {
            logger.warning("⏰ timed out after \(target.timeoutInterval)s, retrying once: \(target.path, privacy: .public)")
            return try await request(target, responseType: responseType)
        }
    }
}
