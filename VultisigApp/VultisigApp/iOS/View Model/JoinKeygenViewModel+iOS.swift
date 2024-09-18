//
//  JoinKeygenViewModel+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension JoinKeygenViewModel {
    func handleScan(result: Result<ScanResult, ScanError>) {
        defer {
            isShowingScanner = false
        }
        
        guard let isCameraPermissionGranted, isCameraPermissionGranted else {
            status = .NoCameraAccess
            return
        }
        
        switch result {
        case .success(let result):
            let url = URL(string: result.string)
            guard
                let json = DeeplinkViewModel.getJsonData(url),
                let tssTypeString = DeeplinkViewModel.getTssType(url),
                let tssType = TssType(rawValue: tssTypeString) else {
                status = .FailToStart
                return
            }
            handleQrCodeSuccessResult(scanData: json, tssType: tssType)

        case .failure(_):
            errorMessage = "Unable to scan the QR code. Please import an image using the button below."
            status = .FailToStart
            return
        }
    }
}
#endif
