//
//  VultiServerService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import Foundation

struct VultiServerService {
    private let httpClient: HTTPClientProtocol
    private let decoder = JSONDecoder()
    
    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }
    
    func resendVaultShare(request: ResendVaultShareRequest) async throws {
        _ = try await httpClient.request(VultiServerAPI.resendVaultShare(request: request))
    }
}
