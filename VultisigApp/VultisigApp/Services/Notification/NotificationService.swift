//
//  NotificationService.swift
//  VultisigApp
//

import Foundation

struct NotificationService {
    let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func registerDevice(request: DeviceRegistrationRequest) async throws {
        _ = try await httpClient.requestEmpty(NotificationAPI.register(payload: request))
    }

    func isVaultRegistered(vaultId: String) async throws -> Bool {
        let response = try await httpClient.request(NotificationAPI.isVaultRegistered(vaultId: vaultId))
        return response.response.statusCode == 200
    }

    func sendNotification(request: NotifyRequest) async throws {
        _ = try await httpClient.requestEmpty(NotificationAPI.notify(payload: request))
    }
}
