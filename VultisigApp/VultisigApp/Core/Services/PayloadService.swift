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

/// TargetType for the relay server payload endpoints. `baseURL` is carried as
/// an associated value because the relay host is selected per-session at
/// construction time, not a global constant.
enum PayloadAPI: TargetType {
    case upload(baseURL: URL, hash: String, payload: String)
    case get(baseURL: URL, hash: String)

    var baseURL: URL {
        switch self {
        case .upload(let url, _, _), .get(let url, _):
            return url
        }
    }

    var path: String {
        switch self {
        case .upload(_, let hash, _), .get(_, let hash):
            return "/payload/\(hash)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .upload: return .post
        case .get: return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .upload(_, _, let payload):
            return .requestData(payload.data(using: .utf8) ?? Data())
        case .get:
            return .requestPlain
        }
    }
}

final class PayloadService {
    internal let serverURL: String
    private let httpClient: HTTPClientProtocol

    init(serverURL: String, httpClient: HTTPClientProtocol = HTTPClient()) {
        self.serverURL = serverURL
        self.httpClient = httpClient
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
        guard let baseURL = URL(string: serverURL) else {
            throw PayloadServiceError.NetworkError(message: "invalid server url: \(serverURL)")
        }
        do {
            _ = try await httpClient.request(PayloadAPI.upload(baseURL: baseURL, hash: hash, payload: payload))
        } catch {
            throw PayloadServiceError.NetworkError(message: "fail to upload payload to relay server: \(error)")
        }
        return hash
    }

    func getPayload(hash: String) async throws -> String {
        guard let baseURL = URL(string: serverURL) else {
            throw PayloadServiceError.NetworkError(message: "invalid server url: \(serverURL)")
        }
        do {
            let response = try await httpClient.request(PayloadAPI.get(baseURL: baseURL, hash: hash))
            guard let payload = String(data: response.data, encoding: .utf8) else {
                throw PayloadServiceError.NetworkError(message: "relay returned a non-UTF8 payload")
            }
            return payload
        } catch let error as PayloadServiceError {
            throw error
        } catch {
            throw PayloadServiceError.NetworkError(message: "fail to get payload from relay server: \(error)")
        }
    }
}
