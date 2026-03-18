//
//  VultiServerService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import Foundation

enum ResendVaultShareError: Error, LocalizedError {
    case tooManyRequests
    case badRequest
    case unknown

    var errorDescription: String? {
        switch self {
        case .tooManyRequests:
            return "requestServerVaultShareTooManyRequestsError".localized
        case .badRequest:
            return "requestServerVaultShareBadRequestError".localized
        case .unknown:
            return "requestServerVaultShareUnknownError".localized
        }
    }
}

struct VultiServerService {
    private let httpClient: HTTPClientProtocol
    private let decoder = JSONDecoder()

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func resendVaultShare(request: ResendVaultShareRequest) async throws {
        do {
            _ = try await httpClient.request(VultiServerAPI.resendVaultShare(request: request))
            return
        } catch {
            guard case let .statusCode(code, _) = error as? HTTPError else {
                throw ResendVaultShareError.unknown
            }
            switch code {
            case 400:
                throw ResendVaultShareError.badRequest
            case 429:
                throw ResendVaultShareError.tooManyRequests
            default:
                throw ResendVaultShareError.unknown
            }
        }
    }
}
