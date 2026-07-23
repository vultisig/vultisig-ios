//
//  NotificationService.swift
//  VultisigApp
//

import Foundation

protocol NotificationServicing {
    func registerDevice(request: DeviceRegistrationRequest) async throws
    func unregisterDevice(vaultId: String, partyName: String) async throws
    func sendNotification(request: NotifyRequest) async throws
}

struct NotificationService: NotificationServicing {
    let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func registerDevice(request: DeviceRegistrationRequest) async throws {
        _ = try await httpClient.requestEmpty(NotificationAPI.register(payload: request))
    }

    func unregisterDevice(vaultId: String, partyName: String) async throws {
        let request = DeviceUnregisterRequest(vaultId: vaultId, partyName: partyName)
        _ = try await httpClient.requestEmpty(
            NotificationAPI.unregister(payload: request)
        )
    }

    func sendNotification(request: NotifyRequest) async throws {
        _ = try await httpClient.requestEmpty(NotificationAPI.notify(payload: request))
    }
}
