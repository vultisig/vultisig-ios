//
//  SecurityScannerServiceFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

enum SecurityScannerServiceFactory {
    static func buildSecurityScannerService() -> SecurityScannerService {
        SecurityScannerService(
            providers: [
                BlockaidScannerService(blockaidRpcClient: BlockaidRpcClient(httpClient: HTTPClient()))
            ],
            settingsService: SecurityScannerSettingsService(),
            factory: SecurityScannerTransactionFactory()
        )
    }
}
