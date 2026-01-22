//
//  HTTPClient.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation
import OSLog

/// Concrete implementation of HTTPClientProtocol using URLSession
public final class HTTPClient: HTTPClientProtocol {

    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger

    /// Initializes HTTPClient with custom URLSession and codecs
    /// - Parameters:
    ///   - session: URLSession to use for requests (default: .shared)
    ///   - jsonEncoder: JSONEncoder for encoding request bodies (default: JSONEncoder())
    ///   - jsonDecoder: JSONDecoder for decoding responses (default: JSONDecoder())
    ///   - logger: Logger for request/response logging (default: Logger for http-client)
    public init(
        session: URLSession = .shared,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "http-client")
    ) {
        self.session = session
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
        self.logger = logger
    }

    /// Performs a network request and returns raw data
    public func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        // Check for cancellation before starting
        try Task.checkCancellation()

        let urlRequest = try buildURLRequest(from: target)

        // Log the request
        logRequest(urlRequest, target: target)

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid HTTP response received")
                throw HTTPError.invalidResponse
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logResponse(httpResponse, data: data, duration: duration)

            try validateResponse(httpResponse, data: data, validationType: target.validationType)

            return HTTPResponse(data: data, response: httpResponse)

        } catch let error as HTTPError {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logError(error, duration: duration)
            throw error
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let httpError: HTTPError
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    httpError = HTTPError.timeout
                case .cancelled:
                    // Re-throw the cancellation error directly so it can be handled upstream
                    logger.warning("⚠️ Request cancelled - \(Int(duration * 1000))ms")
                    throw CancellationError()
                default:
                    httpError = HTTPError.networkError(error)
                }
            } else if error is CancellationError {
                // Handle Swift Concurrency cancellation
                logger.warning("⚠️ Request cancelled - \(Int(duration * 1000))ms")
                throw error
            } else {
                httpError = HTTPError.networkError(error)
            }
            logError(httpError, duration: duration)
            throw httpError
        }
    }
}

// MARK: - Private Methods
private extension HTTPClient {

    /// Builds URLRequest from TargetType
    func buildURLRequest(from target: TargetType) throws -> URLRequest {
        let url = target.baseURL.appendingPathComponent(target.path)
        var urlRequest = URLRequest(url: url, timeoutInterval: target.timeoutInterval)

        urlRequest.httpMethod = target.method.rawValue

        // Set headers
        target.headers?.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Handle task configuration
        try configureRequest(&urlRequest, with: target.task)

        return urlRequest
    }

    /// Configures URLRequest based on Task type
    func configureRequest(_ request: inout URLRequest, with task: HTTPTask) throws {
        switch task {
        case .requestPlain:
            break

        case .requestParameters(let parameters, let encoding):
            try encodeParameters(parameters, encoding: encoding, request: &request)

        case .requestData(let data):
            request.httpBody = data

        case .requestCompositeData(let bodyData, let urlParameters):
            request.httpBody = bodyData
            try encodeParameters(urlParameters, encoding: .urlEncoding, request: &request)

        case .requestCodable(let codable, let encoding):
            try encodeCodable(codable, encoding: encoding, request: &request)
        }
    }

    /// Encodes parameters based on encoding type
    func encodeParameters(_ parameters: [String: Any], encoding: ParameterEncoding, request: inout URLRequest) throws {
        switch encoding {
        case .urlEncoding:
            try encodeURLParameters(parameters, request: &request)

        case .jsonEncoding:
            try encodeJSONParameters(parameters, request: &request)

        case .formEncoding:
            try encodeFormParameters(parameters, request: &request)
        }
    }

    /// Encodes parameters as URL query parameters
    func encodeURLParameters(_ parameters: [String: Any], request: inout URLRequest) throws {
        guard let url = request.url else {
            throw HTTPError.invalidURL
        }

        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        for (key, value) in parameters {
            let valueString = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(value)"
            let queryItem = URLQueryItem(name: key, value: valueString)
            queryItems.append(queryItem)
        }

        urlComponents?.queryItems = queryItems
        request.url = urlComponents?.url
    }

    /// Encodes parameters as JSON in request body
    func encodeJSONParameters(_ parameters: [String: Any], request: inout URLRequest) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: parameters, options: [])
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } catch {
            throw HTTPError.encodingFailed
        }
    }

    /// Encodes parameters as form data
    func encodeFormParameters(_ parameters: [String: Any], request: inout URLRequest) throws {
        let formData = parameters
            .compactMap { key, value in
                guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let encodedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    return nil
                }
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        guard let data = formData.data(using: .utf8) else {
            throw HTTPError.encodingFailed
        }

        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    }

    /// Encodes Codable object based on encoding type
    func encodeCodable(_ codable: Encodable, encoding: ParameterEncoding, request: inout URLRequest) throws {
        switch encoding {
        case .jsonEncoding:
            try encodeCodableAsJSON(codable, request: &request)
        case .urlEncoding:
            // Convert Codable to dictionary, then encode as URL parameters
            let dictionary = try codable.toDictionary()
            try encodeURLParameters(dictionary, request: &request)
        case .formEncoding:
            // Convert Codable to dictionary, then encode as form data
            let dictionary = try codable.toDictionary()
            try encodeFormParameters(dictionary, request: &request)
        }
    }

    /// Encodes Codable object as JSON
    func encodeCodableAsJSON(_ codable: Encodable, request: inout URLRequest) throws {
        do {
            let data = try jsonEncoder.encode(codable)
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } catch {
            throw HTTPError.encodingFailed
        }
    }

    /// Validates HTTP response based on validation type
    func validateResponse(_ response: HTTPURLResponse, data: Data, validationType: ValidationType) throws {
        switch validationType {
        case .noValidation:
            break

        case .successCodes:
            if !(200...299).contains(response.statusCode) {
                throw HTTPError.statusCode(response.statusCode, data)
            }

        case .customCodes(let codes):
            if !codes.contains(response.statusCode) {
                throw HTTPError.statusCode(response.statusCode, data)
            }
        }
    }
}

// MARK: - Logging Methods
private extension HTTPClient {

    /// Logs the outgoing HTTP request
    func logRequest(_ request: URLRequest, target: TargetType) {
        guard let url = request.url else { return }

        logger.info("🚀 HTTP Request: \(request.httpMethod ?? "GET") \(url.absoluteString)")

        // Log headers
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            logger.debug("📋 Headers: \(headers)")
        }

        // Log body (if present and reasonable size)
        if let body = request.httpBody {
            if body.count < 1024, let bodyString = String(data: body, encoding: .utf8) {
                logger.debug("📦 Body: \(bodyString)")
            } else {
                logger.debug("📦 Body: \(body.count) bytes")
            }
        }

        logger.debug("⏱️ Timeout: \(target.timeoutInterval)s")
    }

    /// Logs the HTTP response
    func logResponse(_ response: HTTPURLResponse, data: Data, duration: TimeInterval) {
        let statusIcon = getStatusIcon(for: response.statusCode)
        let durationMs = Int(duration * 1000)

        logger.info("\(statusIcon) HTTP Response: \(response.statusCode) - \(durationMs)ms - \(data.count) bytes")

        // Log response body for debugging (only if it's reasonable size and JSON/text)
        if data.count < 2048,
           let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("json") || contentType.contains("text"),
           let responseString = String(data: data, encoding: .utf8) {
            logger.debug("📥 Response: \(responseString)")
        }
    }

    /// Logs HTTP errors
    func logError(_ error: HTTPError, duration: TimeInterval) {
        let durationMs = Int(duration * 1000)

        switch error {
        case .statusCode(let code, let data):
            logger.error("❌ HTTP Error: \(code) - \(durationMs)ms")
            if let data = data, data.count < 1024,
               let errorString = String(data: data, encoding: .utf8) {
                logger.error("🔍 Error Details: \(errorString)")
            }
        case .timeout:
            logger.error("⏰ HTTP Timeout after \(durationMs)ms")
        case .networkError(let underlying):
            logger.error("🌐 Network Error: \(underlying.localizedDescription) - \(durationMs)ms")
        default:
            logger.error("💥 HTTP Error: \(error.localizedDescription) - \(durationMs)ms")
        }
    }

    /// Gets appropriate emoji for HTTP status code
    func getStatusIcon(for statusCode: Int) -> String {
        switch statusCode {
        case 200...299:
            return "✅"
        case 300...399:
            return "🔄"
        case 400...499:
            return "⚠️"
        case 500...599:
            return "❌"
        default:
            return "❓"
        }
    }
}

// MARK: - Encodable Extension

extension Encodable {
    /// Converts Encodable to dictionary for URL/form encoding
    func toDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

        guard let dictionary = jsonObject as? [String: Any] else {
            throw HTTPError.encodingFailed
        }

        return dictionary
    }
}
